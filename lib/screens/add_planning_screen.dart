import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/activity_log_service.dart';
import '../services/renom_auth_service.dart';
import '../widgets/searchable_dropdown.dart';

class AddPlanningScreen extends StatefulWidget {
  final String? assignedState;

  const AddPlanningScreen({super.key, this.assignedState});

  @override
  State<AddPlanningScreen> createState() => _AddPlanningScreenState();
}

class _AddPlanningScreenState extends State<AddPlanningScreen> {
  final _formKey = GlobalKey<FormState>();
  
  String? _selectedStateId;
  String? _selectedStateName;
  String? _selectedSiteId;
  String? _selectedSiteName;
  String? _selectedModelId;
  String? _selectedModelName;
  
  bool _isStateLocked = false;

  DateTime? _plannedDate;
  final TextEditingController _dateController = TextEditingController();
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
  }

  Future<void> _fetchUserProfile() async {
    final renomUser = RenomAuthService.instance.currentUser;
    String? assignedStateName = (widget.assignedState != null &&
            widget.assignedState!.trim().isNotEmpty &&
            widget.assignedState!.trim().toLowerCase() != 'all')
        ? widget.assignedState!.trim()
        : (renomUser != null &&
                renomUser.assignedState.isNotEmpty &&
                renomUser.assignedState.toLowerCase() != 'all')
            ? renomUser.assignedState.trim()
            : null;

    String? assignedStateId;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>;
          final fState = data['assigned_state']?.toString().trim();
          if (fState != null && fState.isNotEmpty && fState.toLowerCase() != 'all') {
            assignedStateName ??= fState;
          }
          final fId = data['assigned_state_id']?.toString().trim();
          if (fId != null && fId.isNotEmpty) {
            assignedStateId = fId;
          }
        }
      } catch (e) {
        debugPrint('Error fetching user profile in AddPlanningScreen: $e');
      }
    }

    if (assignedStateName != null && assignedStateName.isNotEmpty) {
      if (assignedStateId == null || assignedStateId.isEmpty) {
        try {
          final stateQuery = await FirebaseFirestore.instance
              .collection('states')
              .where('state', isEqualTo: assignedStateName)
              .limit(1)
              .get();
          if (stateQuery.docs.isNotEmpty) {
            assignedStateId = stateQuery.docs.first.id;
          }
        } catch (e) {
          debugPrint('Error recovering state ID: $e');
        }
      }

      if (mounted && assignedStateId != null) {
        setState(() {
          _selectedStateId = assignedStateId;
          _selectedStateName = assignedStateName;
          _isStateLocked = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _dateController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF00897B),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _plannedDate) {
      setState(() {
        _plannedDate = picked;
        _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _savePlan() async {
    if (!_formKey.currentState!.validate()) return;
    if (_plannedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a planned date')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      // Name Logic
      final renomUser = RenomAuthService.instance.currentUser;
      var actualName = 'Auditor';
      String auditorId = user.uid;

      if (renomUser != null && renomUser.name.isNotEmpty) {
        actualName = renomUser.name;
        if (renomUser.docId.isNotEmpty) {
          auditorId = renomUser.docId;
        }
      } else if (user.email == '2164@renom.com') {
        actualName = 'Ankit Kumawat';
      } else if (user.displayName != null && user.displayName!.isNotEmpty) {
        actualName = user.displayName!;
      } else {
        actualName = user.email?.split('@')[0] ?? 'Auditor';
      }

      // Strict Schema Submission
      await FirebaseFirestore.instance.collection('planning_data').add({
        // 1. Auditor Details
        'auditor_id': auditorId,
        'auditor_name': actualName,
        'auditors': [actualName],

        // 2. Dates
        'created_at': FieldValue.serverTimestamp(),
        'planned_date': Timestamp.fromDate(_plannedDate!),

        // 3. Location & References
        'site_name': _selectedSiteName,
        'site_ref': FirebaseFirestore.instance.doc('/sites/$_selectedSiteId'),
        
        'state': _selectedStateName,
        'state_ref': FirebaseFirestore.instance.doc('/states/$_selectedStateId'),

        // 4. Turbine Details
        'turbine_model': _selectedModelName,
        'turbinemodel_ref': FirebaseFirestore.instance.doc('/turbinemodel/$_selectedModelId'),
        'number_of_turbines': 1,

        // 5. Status
        'status': 'pending_approval',
      });

      // Log plan creation event
      await ActivityLogService.instance.logActivity(
        actionType: 'AUDIT_PLAN_ADD',
        description: 'Created audit plan for $_selectedSiteName',
        metadata: {
          'siteId': _selectedSiteId,
          'siteName': _selectedSiteName,
          'stateId': _selectedStateId,
          'stateName': _selectedStateName,
          'modelId': _selectedModelId,
          'modelName': _selectedModelName,
          'plannedDate': _plannedDate?.toIso8601String(),
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Plan submitted for approval'), 
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving plan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Add New Plan',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStateDropdown(),
              const SizedBox(height: 16),
              _buildSiteDropdown(),
              const SizedBox(height: 16),
              _buildModelDropdown(),
              const SizedBox(height: 16),
              TextFormField(
                controller: _dateController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Planned Date',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: Colors.grey[100],
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                onTap: () => _selectDate(context),
                validator: (value) => value == null || value.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _savePlan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Save Plan',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStateDropdown() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('states').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final states = snapshot.data!.docs;
        final items = states.map((state) {
          return SearchableDropdownItem<String>(
            value: state.id,
            label: state.get('state') as String,
            icon: Icons.location_on_outlined,
          );
        }).toList();
        
        return SearchableDropdown<String>(
          items: items,
          selectedValue: _selectedStateId,
          labelText: 'State',
          hintText: 'Search states...',
          prefixIcon: Icons.location_on_outlined,
          enabled: !_isStateLocked,
          disabledHint: _selectedStateName ?? 'Assigned state',
          onChanged: _isStateLocked 
              ? null 
              : (value) {
                  setState(() {
                    _selectedStateId = value;
                    _selectedStateName = states
                        .firstWhere((doc) => doc.id == value)
                        .get('state') as String?;
                    _selectedSiteId = null;
                    _selectedSiteName = null;
                    _selectedModelId = null;
                    _selectedModelName = null;
                  });
                },
        );
      },
    );
  }

  Widget _buildSiteDropdown() {
    if (_selectedStateId == null) {
      return const SearchableDropdown<String>(
        items: [],
        selectedValue: null,
        labelText: 'Site',
        hintText: 'Select state first',
        prefixIcon: Icons.business_outlined,
        enabled: false,
        disabledHint: 'Select state first',
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('sites')
          .where('state_ref', isEqualTo: FirebaseFirestore.instance.collection('states').doc(_selectedStateId))
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final sites = snapshot.data!.docs;
        final items = sites.map((site) {
          return SearchableDropdownItem<String>(
            value: site.id,
            label: site.get('site_name') as String,
            icon: Icons.business_outlined,
          );
        }).toList();
        
        return SearchableDropdown<String>(
          items: items,
          selectedValue: _selectedSiteId,
          labelText: 'Site',
          hintText: 'Search sites...',
          prefixIcon: Icons.business_outlined,
          onChanged: (value) {
            final selectedDoc = sites.firstWhere((doc) => doc.id == value);
            setState(() {
              _selectedSiteId = value;
              _selectedSiteName = selectedDoc.get('site_name') as String?;
              _selectedModelId = null;
              _selectedModelName = null;
            });
          },
        );
      },
    );
  }

  Widget _buildModelDropdown() {
    if (_selectedSiteId == null) {
      return const SearchableDropdown<String>(
        items: [],
        selectedValue: null,
        labelText: 'Turbine Model',
        hintText: 'Select site first',
        prefixIcon: Icons.wind_power_outlined,
        enabled: false,
        disabledHint: 'Select site first',
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('turbinemodel').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final allModels = snapshot.data!.docs;
        
        // Filter models based on selected site (supporting both new and legacy schema)
        final filteredModels = allModels.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final siteRef = FirebaseFirestore.instance.collection('sites').doc(_selectedSiteId);

          // Check new schema: site_ids array (can contain String IDs or DocumentReferences)
          if (data.containsKey('site_ids') && data['site_ids'] is List) {
            final siteIds = data['site_ids'] as List<dynamic>;
            if (siteIds.contains(_selectedSiteId) || siteIds.contains(siteRef)) {
              return true;
            }
          }
          
          // Check legacy schema: site_ref
          if (data.containsKey('site_ref') && data['site_ref'] is DocumentReference) {
            final ref = data['site_ref'] as DocumentReference<Object?>;
            if (ref.id == _selectedSiteId || ref == siteRef) {
              return true;
            }
          }
          
          return false;
        }).toList();
        
        // Auto-select if only one model is available
        if (filteredModels.length == 1 && _selectedModelId == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _selectedModelId = filteredModels.first.id;
                _selectedModelName = filteredModels.first.get('turbine_model') as String?;
              });
            }
          });
        }
        
        final items = filteredModels.map((model) {
          return SearchableDropdownItem<String>(
            value: model.id,
            label: model.get('turbine_model') as String,
            icon: Icons.wind_power_outlined,
          );
        }).toList();
        
        return SearchableDropdown<String>(
          items: items,
          selectedValue: _selectedModelId,
          labelText: 'Turbine Model',
          hintText: filteredModels.length == 1 ? 'Auto-selected (single model)' : 'Search turbine models...',
          prefixIcon: Icons.wind_power_outlined,
          onChanged: (value) {
            final selectedDoc = filteredModels.firstWhere((doc) => doc.id == value);
            setState(() {
              _selectedModelId = value;
              _selectedModelName = selectedDoc.get('turbine_model') as String?;
            });
          },
        );
      },
    );
  }
}
