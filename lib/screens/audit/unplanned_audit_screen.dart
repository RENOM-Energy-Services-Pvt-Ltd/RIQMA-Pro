import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/audit_manager.dart';
import '../../services/renom_master_data_service.dart';
import '../../widgets/searchable_dropdown.dart';
import '../audit_main_categories_screen.dart';

class UnplannedAuditScreen extends StatefulWidget {
  final String? assignedState;

  const UnplannedAuditScreen({super.key, this.assignedState});

  @override
  State<UnplannedAuditScreen> createState() => _UnplannedAuditScreenState();
}

class _UnplannedAuditScreenState extends State<UnplannedAuditScreen> {
  // Master Data
  List<Map<String, dynamic>> _allStates = [];
  List<Map<String, dynamic>> _allSites = [];
  List<Map<String, dynamic>> _allModels = [];
  List<Map<String, dynamic>> _allTurbines = [];

  // Filtered Data
  List<Map<String, dynamic>> _visibleSites = [];
  List<Map<String, dynamic>> _visibleModels = [];
  List<Map<String, dynamic>> _visibleTurbines = [];

  // Selections
  String? _selectedStateId;
  String? _selectedSiteId;
  String? _selectedModelId;
  String? _selectedTurbineId;

  bool _isLoading = true;
  bool _hasDraft = false;
  Map<String, dynamic>? _draftData;

  @override
  void initState() {
    super.initState();
    _fetchMasterData();
    _checkDraft();
  }

  Future<void> _checkDraft() async {
    final hasDraft = await AuditManager.instance.hasDraft();
    if (hasDraft) {
      final data = await AuditManager.instance.getDraftMetadata();
      if (mounted) {
        setState(() {
          _hasDraft = true;
          _draftData = data;
        });
      }
    }
  }

  Future<void> _fetchMasterData() async {
    try {
      // 1. Fetch from Renom Server API (with automatic local cache & Firestore fallback)
      final renomStates = await RenomMasterDataService.instance.getStates();
      final renomSites = await RenomMasterDataService.instance.getSites();
      final renomTurbineData = await RenomMasterDataService.instance.getTurbinesAndModels();

      final List<Map<String, dynamic>> states = renomStates;
      final List<Map<String, dynamic>> sites = renomSites;
      final List<Map<String, dynamic>> models = renomTurbineData['models'] ?? [];
      final List<Map<String, dynamic>> turbines = renomTurbineData['turbines'] ?? [];

      if (states.isNotEmpty && sites.isNotEmpty) {
        setState(() {
          _allStates = states.map((s) => <String, dynamic>{
            'reference': FirebaseFirestore.instance.collection('states').doc(s['id'].toString()),
            ...s,
          }).toList();

          _allSites = sites.map((s) => <String, dynamic>{
            'reference': FirebaseFirestore.instance.collection('sites').doc(s['id'].toString()),
            ...s,
          }).toList();

          _allModels = models.map((m) => <String, dynamic>{
            'reference': FirebaseFirestore.instance.collection('turbinemodel').doc(m['id'].toString()),
            ...m,
          }).toList();

          _allTurbines = turbines.map((t) => <String, dynamic>{
            'reference': FirebaseFirestore.instance.collection('turbinename').doc(t['id'].toString()),
            ...t,
          }).toList();

          _isLoading = false;
        });
      } else {
        // Fallback: Direct Firestore fetch
        final results = await Future.wait([
          FirebaseFirestore.instance.collection('states').get(),
          FirebaseFirestore.instance.collection('sites').get(),
          FirebaseFirestore.instance.collection('turbinemodel').get(),
          FirebaseFirestore.instance.collection('turbinename').get(),
        ]);

        setState(() {
          _allStates = results[0].docs.map((doc) => {'id': doc.id, 'reference': doc.reference, ...doc.data()}).toList();
          _allSites = results[1].docs.map((doc) => {'id': doc.id, 'reference': doc.reference, ...doc.data()}).toList();
          _allModels = results[2].docs.map((doc) => {'id': doc.id, 'reference': doc.reference, ...doc.data()}).toList();
          _allTurbines = results[3].docs.map((doc) => {'id': doc.id, 'reference': doc.reference, ...doc.data()}).toList();
          _isLoading = false;
        });
      }

      // Apply User Restriction if assignedState is present
      if (widget.assignedState != null && widget.assignedState!.isNotEmpty && widget.assignedState != 'All') {
        final assigned = widget.assignedState!.trim().toLowerCase();
        final matchingState = _allStates.firstWhere(
          (doc) => (doc['state']?.toString().trim().toLowerCase() == assigned) ||
                   (doc['name']?.toString().trim().toLowerCase() == assigned),
          orElse: () => _allStates.isNotEmpty ? _allStates.first : {},
        );
        
        if (matchingState.isNotEmpty) {
          _onStateSelected(matchingState['id'] as String?);
        }
      }
    } catch (e) {
      debugPrint('Error fetching master data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  void _onStateSelected(String? stateId) {
    if (stateId == null) return;

    setState(() {
      _selectedStateId = stateId;
      _selectedSiteId = null;
      _selectedModelId = null;
      _selectedTurbineId = null;

      final stateDoc = _allStates.firstWhere((s) => s['id'] == stateId, orElse: () => {});
      final stateName = stateDoc['name']?.toString() ?? stateDoc['state']?.toString() ?? '';
      final stateRef = FirebaseFirestore.instance.collection('states').doc(stateId);

      _visibleSites = _allSites.where((doc) {
        // Match by state_id (Renom API)
        if (doc['state_id'] != null && doc['state_id'].toString() == stateId) return true;
        // Match by state name
        if (stateName.isNotEmpty && (doc['state_name'] == stateName || doc['state'] == stateName)) return true;
        // Match by Firestore DocumentReference
        final ref = doc['state_ref'] as DocumentReference?;
        return ref == stateRef || ref?.id == stateId;
      }).toList();

      _visibleModels = [];
      _visibleTurbines = [];
    });
  }

  void _onSiteSelected(String? siteId) {
    if (siteId == null) return;

    setState(() {
      _selectedSiteId = siteId;
      _selectedModelId = null;
      _selectedTurbineId = null;

      final siteDoc = _allSites.firstWhere((s) => s['id'] == siteId, orElse: () => {});
      final siteName = siteDoc['site_name']?.toString() ?? siteDoc['name']?.toString() ?? '';
      final siteRef = FirebaseFirestore.instance.collection('sites').doc(siteId);

      _visibleModels = _allModels.where((doc) {
        // 1. Renom API: Match models that have turbines on this site
        if (_allTurbines.any((t) => (t['site_name'] == siteName || t['site'] == siteName || t['site_id'] == siteId) &&
                                    (t['model'] == doc['name'] || t['turbine_model'] == doc['name'] || t['model'] == doc['id']))) {
          return true;
        }

        // 2. Firestore schema: site_ids array
        if (doc.containsKey('site_ids') && doc['site_ids'] is List) {
          final siteIds = doc['site_ids'] as List<dynamic>;
          if (siteIds.contains(siteRef) || siteIds.contains(siteId)) return true;
        }
        
        // 3. Legacy schema: site_ref
        if (doc.containsKey('site_ref') && doc['site_ref'] is DocumentReference) {
          final ref = doc['site_ref'] as DocumentReference<Object?>;
          if (ref.id == siteId) return true;
        }
        
        return false;
      }).toList();

      _visibleTurbines = [];
    });
  }

  void _onModelSelected(String? modelId) {
    if (modelId == null) return;

    setState(() {
      _selectedModelId = modelId;
      _selectedTurbineId = null;

      final siteDoc = _allSites.firstWhere((s) => s['id'] == _selectedSiteId, orElse: () => {});
      final siteName = siteDoc['site_name']?.toString() ?? siteDoc['name']?.toString() ?? '';
      final modelDoc = _allModels.firstWhere((m) => m['id'] == modelId, orElse: () => {});
      final modelName = modelDoc['name']?.toString() ?? modelDoc['turbine_model']?.toString() ?? modelId;
      final modelRef = FirebaseFirestore.instance.collection('turbinemodel').doc(modelId);

      _visibleTurbines = _allTurbines.where((doc) {
        final matchesSite = (doc['site_name'] == siteName || doc['site'] == siteName || doc['site_id'] == _selectedSiteId);
        final matchesModel = (doc['model'] == modelName || doc['turbine_model'] == modelName || doc['model'] == modelId || doc['turbine_model'] == modelId);
        if (matchesSite && matchesModel) return true;

        final sRef = doc['site_ref'] as DocumentReference?;
        final ref = doc['turbinemodel_ref'] as DocumentReference?;
        return sRef?.id == _selectedSiteId && (ref == modelRef || ref?.id == modelId);
      }).toList();
    });
  }

  Future<void> _discardDraft() async {
    await AuditManager.instance.clearAudit();
    if (mounted) {
      setState(() {
        _hasDraft = false;
        _draftData = null;
        // Reset selections
        _selectedSiteId = null;
        _selectedModelId = null;
        _selectedTurbineId = null;
        // Keep state if assigned
        if (widget.assignedState == null) {
          _selectedStateId = null;
        }
      });
    }
  }

  Future<void> _startAudit() async {
    if (_selectedStateId == null ||
        _selectedSiteId == null ||
        _selectedModelId == null ||
        _selectedTurbineId == null) {
      return;
    }

    final siteDoc = _allSites.firstWhere((doc) => doc['id'] == _selectedSiteId);
    final modelDoc = _allModels.firstWhere((doc) => doc['id'] == _selectedModelId);
    final turbineDoc = _allTurbines.firstWhere((doc) => doc['id'] == _selectedTurbineId);
    final stateDoc = _allStates.firstWhere((doc) => doc['id'] == _selectedStateId);

    final siteName = siteDoc['site_name']?.toString() ?? siteDoc['name']?.toString() ?? 'Unknown Site';
    final turbineName = turbineDoc['turbine_name']?.toString() ?? turbineDoc['name']?.toString() ?? turbineDoc['turbine_id']?.toString() ?? 'Unknown Turbine';
    final stateName = stateDoc['state']?.toString() ?? stateDoc['name']?.toString() ?? 'Unknown State';
    final modelName = modelDoc['turbine_model']?.toString() ?? modelDoc['name']?.toString() ?? 'Unknown Model';

    // Save Draft Metadata
    final unplannedDraftId = 'unplanned_${turbineDoc['id']}';
    await AuditManager.instance.saveDraftMetadata(
      draftId: unplannedDraftId,
      siteId: siteDoc['id'].toString(),
      siteName: siteName,
      turbineId: turbineDoc['id'].toString(),
      turbineName: turbineName,
      stateName: stateName,
      modelId: modelDoc['id'].toString(),
      modelName: modelName,
      planId: 'unplanned',
    );

    if (!mounted) return;

    final DocumentReference modelRef = (modelDoc['reference'] is DocumentReference)
        ? modelDoc['reference'] as DocumentReference<Object?>
        : FirebaseFirestore.instance.collection('turbinemodel').doc(modelDoc['id'].toString());

    final DocumentReference siteRef = (siteDoc['reference'] is DocumentReference)
        ? siteDoc['reference'] as DocumentReference<Object?>
        : FirebaseFirestore.instance.collection('sites').doc(siteDoc['id'].toString());

    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => AuditMainCategoriesScreen(
          siteName: siteName,
          turbineName: turbineName,
          turbineModelRef: modelRef,
          siteRef: siteRef,
          siteId: siteDoc['id'].toString(),
          turbineId: turbineDoc['id'].toString(),
          stateName: stateName,
        ),
      ),
    );
    await _checkDraft(); // Re-check draft when returning
  }

  /// Helper to get current step (0-indexed)
  int _getCurrentStep() {
    if (_selectedTurbineId != null) return 4;
    if (_selectedModelId != null) return 3;
    if (_selectedSiteId != null) return 2;
    if (_selectedStateId != null) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        title: const Text(
          'Unplanned Audit',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: const CircularProgressIndicator(
                color: Color(0xFF00897B),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading data...',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (_hasDraft && _draftData != null) {
      return _buildDraftCard();
    }

    return _buildSelectionForm();
  }

  Widget _buildDraftCard() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with gradient
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFFA726), Color(0xFFFF9800)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.pending_actions,
                      size: 32,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pending Audit',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'You have an incomplete audit',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.location_on, color: Colors.grey.shade600),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _draftData!['siteName']?.toString() ?? 'Unknown Site',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Turbine: ${_draftData!['turbineName'] ?? 'Unknown'}',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _discardDraft,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Discard'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            if (_allSites.isEmpty || _allModels.isEmpty) {
                              return;
                            }

                            final siteDoc = _allSites.firstWhere(
                              (doc) => doc['id'] == _draftData!['siteId'],
                              orElse: () => {},
                            );
                            final modelDoc = _allModels.firstWhere(
                              (doc) => doc['id'] == _draftData!['modelId'],
                              orElse: () => {},
                            );

                            if (siteDoc.isEmpty || modelDoc.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Error: Referenced data not found. Discarding draft.'),
                                ),
                              );
                              await _discardDraft();
                              return;
                            }

                            await Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (context) => AuditMainCategoriesScreen(
                                  siteName: _draftData!['siteName'] as String,
                                  turbineName: _draftData!['turbineName'] as String,
                                  turbineModelRef:
                                      modelDoc['reference'] as DocumentReference<Object?>,
                                  siteRef: siteDoc['reference'] as DocumentReference<Object?>,
                                  siteId: _draftData!['siteId'] as String,
                                  turbineId: _draftData!['turbineId'] as String,
                                  stateName: _draftData!['stateName'] as String,
                                ),
                              ),
                            );
                            await _checkDraft();
                          },
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Resume'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00897B),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionForm() {
    final currentStep = _getCurrentStep();

    return SingleChildScrollView(
      child: Column(
        children: [
          // Header Card with gradient
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00897B), Color(0xFF00695C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00897B).withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.wind_power,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Start New Audit',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Select turbine to begin inspection',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Progress Indicator
                _buildProgressIndicator(currentStep),
              ],
            ),
          ),

          // Selection Cards
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                // State Dropdown
                _buildSelectionCard(
                  stepNumber: 1,
                  isActive: true,
                  isCompleted: _selectedStateId != null,
                  child: SearchableDropdown<String>(
                    labelText: 'State',
                    hintText: 'Search states...',
                    disabledHint: 'State is locked',
                    prefixIcon: Icons.map_outlined,
                    selectedValue: _selectedStateId,
                    enabled: widget.assignedState == null,
                    onChanged: widget.assignedState != null
                        ? null
                        : (value) => _onStateSelected(value),
                    items: _allStates.map((doc) {
                      return SearchableDropdownItem<String>(
                        value: doc['id'] as String,
                        label: doc['state']?.toString() ?? 'N/A',
                        icon: Icons.location_city,
                      );
                    }).toList(),
                  ),
                ),

                // Site Dropdown
                _buildSelectionCard(
                  stepNumber: 2,
                  isActive: _selectedStateId != null,
                  isCompleted: _selectedSiteId != null,
                  child: SearchableDropdown<String>(
                    labelText: 'Site',
                    hintText: 'Search sites...',
                    disabledHint: 'Select State first',
                    prefixIcon: Icons.location_on_outlined,
                    selectedValue: _selectedSiteId,
                    enabled: _selectedStateId != null,
                    onChanged: _selectedStateId == null
                        ? null
                        : (value) => _onSiteSelected(value),
                    items: _visibleSites.map((doc) {
                      return SearchableDropdownItem<String>(
                        value: doc['id'] as String,
                        label: doc['site_name']?.toString() ?? 'N/A',
                        icon: Icons.business,
                      );
                    }).toList(),
                  ),
                ),

                // Model Dropdown
                _buildSelectionCard(
                  stepNumber: 3,
                  isActive: _selectedSiteId != null,
                  isCompleted: _selectedModelId != null,
                  child: SearchableDropdown<String>(
                    labelText: 'Turbine Model',
                    hintText: 'Search models...',
                    disabledHint: 'Select Site first',
                    prefixIcon: Icons.precision_manufacturing_outlined,
                    selectedValue: _selectedModelId,
                    enabled: _selectedSiteId != null,
                    onChanged: _selectedSiteId == null
                        ? null
                        : (value) => _onModelSelected(value),
                    items: _visibleModels.map((doc) {
                      return SearchableDropdownItem<String>(
                        value: doc['id'] as String,
                        label: doc['turbine_model']?.toString() ?? 'N/A',
                        subtitle: doc['turbine_rating']?.toString(),
                        icon: Icons.settings,
                      );
                    }).toList(),
                  ),
                ),

                // Turbine Dropdown
                _buildSelectionCard(
                  stepNumber: 4,
                  isActive: _selectedModelId != null,
                  isCompleted: _selectedTurbineId != null,
                  child: SearchableDropdown<String>(
                    labelText: 'Turbine ID',
                    hintText: 'Search turbines...',
                    disabledHint: 'Select Model first',
                    prefixIcon: Icons.wind_power_outlined,
                    selectedValue: _selectedTurbineId,
                    enabled: _selectedModelId != null,
                    onChanged: _selectedModelId == null
                        ? null
                        : (value) => setState(() => _selectedTurbineId = value),
                    items: _visibleTurbines.map((doc) {
                      return SearchableDropdownItem<String>(
                        value: doc['id'] as String,
                        label: doc['turbine_id']?.toString() ??
                            doc['name']?.toString() ??
                            'N/A',
                        icon: Icons.wind_power,
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 24),

                // Start Audit Button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _selectedTurbineId != null ? _startAudit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00897B),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                      elevation: _selectedTurbineId != null ? 8 : 0,
                      shadowColor: const Color(0xFF00897B).withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _selectedTurbineId != null
                              ? Icons.play_arrow_rounded
                              : Icons.lock_outline,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _selectedTurbineId != null
                              ? 'Start Audit'
                              : 'Complete Selection',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator(int currentStep) {
    return Row(
      children: List.generate(4, (index) {
        final isCompleted = index < currentStep;
        final isActive = index == currentStep;

        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: isCompleted || isActive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (index < 3) const SizedBox(width: 8),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildSelectionCard({
    required int stepNumber,
    required bool isActive,
    required bool isCompleted,
    required Widget child,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      child: Stack(
        children: [
          // Step number badge
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? const Color(0xFF00897B)
                      : isActive
                          ? Colors.white
                          : Colors.grey.shade300,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isActive && !isCompleted
                        ? const Color(0xFF00897B)
                        : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: isCompleted
                      ? [
                          BoxShadow(
                            color: const Color(0xFF00897B).withValues(alpha: 0.3),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : Text(
                          '$stepNumber',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: isActive
                                ? const Color(0xFF00897B)
                                : Colors.grey.shade600,
                          ),
                        ),
                ),
              ),
            ),
          ),
          // Dropdown
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: child,
          ),
        ],
      ),
    );
  }
}
