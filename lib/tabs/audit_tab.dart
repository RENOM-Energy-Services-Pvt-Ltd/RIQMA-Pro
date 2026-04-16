import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/audit/unplanned_audit_screen.dart';
import '../screens/audit_main_categories_screen.dart';
import '../services/sync_service.dart';
import '../widgets/searchable_dropdown.dart';
import '../services/audit_manager.dart';

class AuditTab extends StatefulWidget {
  final String? assignedState;

  const AuditTab({super.key, this.assignedState});

  @override
  State<AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<AuditTab> {
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Center(child: Text('Please log in to view audit plans'));
    }



    return Scaffold(
      body: Column(
        children: [
          // ─── OFFLINE SYNC STATUS BAR ───
          ListenableBuilder(
            listenable: SyncService.instance,
            builder: (context, _) {
              if (!SyncService.instance.isSyncing && !SyncService.instance.isReady) {
                return const SizedBox.shrink();
              }
              
              final isReady = SyncService.instance.isReady;
              final isSyncing = SyncService.instance.isSyncing;
              
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isReady 
                      ? const Color(0xFFE8F5E9) 
                      : const Color(0xFFE3F2FD),
                  border: Border(
                    bottom: BorderSide(
                      color: isReady 
                          ? Colors.green.withValues(alpha: 0.2) 
                          : Colors.blue.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isReady ? Icons.cloud_done_rounded : Icons.sync_rounded,
                      size: 18,
                      color: isReady ? Colors.green[700] : Colors.blue[700],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            SyncService.instance.statusMessage ?? 'Syncing...',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isReady ? Colors.green[900] : Colors.blue[900],
                            ),
                          ),
                          if (isSyncing) ...[
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: SyncService.instance.progress,
                                minHeight: 4,
                                backgroundColor: Colors.blue.withValues(alpha: 0.1),
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[700]!),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isReady)
                      Icon(Icons.check_circle, size: 16, color: Colors.green[700]),
                  ],
                ),
              );
            },
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('planning_data')
                  .where('auditor_id', isEqualTo: _currentUser!.uid)
                  .where('status', isEqualTo: 'approved')
                  // .orderBy('planned_date', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.assignment_turned_in_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No pending audits found', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final docId = docs[index].id;
              
              // Extract data safely

              // Helper Logic inside the list builder
              final plannedTs = data['planned_date'] as Timestamp?;
              var statusText = 'No Date';
              Color statusColor = Colors.grey;
              
              if (plannedTs != null) {
                final plannedDate = plannedTs.toDate();
                final now = DateTime.now();
                // Reset times to compare dates only
                final today = DateTime(now.year, now.month, now.day);
                final target = DateTime(plannedDate.year, plannedDate.month, plannedDate.day);
                
                final diff = target.difference(today).inDays;
                
                if (diff > 0) {
                  statusText = '$diff Days Left';
                  statusColor = Colors.green[700]!;
                } else if (diff < 0) {
                   statusText = 'Delayed by ${diff.abs()} Days';
                   statusColor = Colors.red[700]!;
                } else {
                  statusText = 'Scheduled Today';
                  statusColor = Colors.blue[700]!;
                }
              }

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE0F2F1), // Teal 50
                    child: Icon(Icons.wind_power, color: Color(0xFF00897B)),
                  ),
                  title: Text(
                    '${data['site_name']} - ${data['turbine_model'] ?? 'Unknown Model'}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  trailing: plannedTs != null
                      ? Text(
                          DateFormat('dd MMM yy').format(plannedTs.toDate()),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1A1F36),
                          ),
                        )
                      : null,
                  onTap: () => _activeAuditPlan(context, data, docId),
                ),
              );
            },
          );
        },
      ),
    ),
  ],
),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (context) => UnplannedAuditScreen(assignedState: widget.assignedState),
            ),
          );
        },
        label: const Text('Unplanned Audit'),
        icon: const Icon(Icons.add_task),
        backgroundColor: const Color(0xFF00897B),
      ),
    );
  }

  void _activeAuditPlan(BuildContext context, Map<String, dynamic> planData, String planId) {
    if (planData['site_ref'] is! DocumentReference || planData['turbinemodel_ref'] is! DocumentReference) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Error: Invalid Data Format. Please delete this plan and create a new one.'),
        backgroundColor: Colors.red,
      ));
      return; 
    }
    
    _showAuditWizard(context, planData, planId);
  }

  /// Full 4-step wizard bottom-sheet: State → Site → Model → Turbine.
  /// Pre-populated from planData but allows overrides.
  Future<void> _showAuditWizard(BuildContext context, Map<String, dynamic> planData, String planId) async {
    // Master data lists
    var allStates = <Map<String, dynamic>>[];
    var allSites = <Map<String, dynamic>>[];
    var allModels = <Map<String, dynamic>>[];
    var allTurbines = <Map<String, dynamic>>[];

    // Filtered lists
    var visibleSites = <Map<String, dynamic>>[];
    var visibleModels = <Map<String, dynamic>>[];
    var visibleTurbines = <Map<String, dynamic>>[];

    // Selections
    String? selectedStateId;
    String? selectedSiteId;
    String? selectedModelId;
    String? selectedTurbineId;

    var isLoading = true;

    // --- Cascade helpers ---
    void applyStateFilter(String stateId, void Function(void Function()) setSheetState) {
      selectedStateId = stateId;
      selectedSiteId = null;
      selectedModelId = null;
      selectedTurbineId = null;

      final stateRef = FirebaseFirestore.instance.collection('states').doc(stateId);
      visibleSites = allSites.where((doc) {
        final ref = doc['state_ref'] as DocumentReference?;
        return ref == stateRef;
      }).toList();
      visibleModels = [];
      visibleTurbines = [];
      setSheetState(() {});
    }

    void applySiteFilter(String siteId, void Function(void Function()) setSheetState) {
      selectedSiteId = siteId;
      selectedModelId = null;
      selectedTurbineId = null;

      final siteRef = FirebaseFirestore.instance.collection('sites').doc(siteId);

      visibleModels = allModels.where((doc) {
        if (doc.containsKey('site_ids') && doc['site_ids'] is List) {
          final siteIds = doc['site_ids'] as List<dynamic>;
          if (siteIds.contains(siteRef) || siteIds.contains(siteId)) return true;
        }
        if (doc.containsKey('site_ref') && doc['site_ref'] is DocumentReference) {
          final ref = doc['site_ref'] as DocumentReference<Object?>;
          if (ref.id == siteId) return true;
        }
        return false;
      }).toList();
      visibleTurbines = [];
      setSheetState(() {});
    }

    void applyModelFilter(String modelId, void Function(void Function()) setSheetState) {
      selectedModelId = modelId;
      selectedTurbineId = null;

      final modelRef = FirebaseFirestore.instance.collection('turbinemodel').doc(modelId);
      visibleTurbines = allTurbines.where((doc) {
        final siteRef = doc['site_ref'] as DocumentReference?;
        final ref = doc['turbinemodel_ref'] as DocumentReference?;
        return siteRef?.id == selectedSiteId && ref == modelRef;
      }).toList();
      setSheetState(() {});
    }

    final turbineDrafts = <String, bool>{};
    if (visibleTurbines.isNotEmpty) {
      for (var turbine in visibleTurbines) {
        final dId = '${planId}_${turbine['id']}';
        final exists = await AuditManager.draftExists(dId);
        turbineDrafts[turbine['id'] as String] = exists;
      }
    }

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 400),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Material(
              color: Colors.transparent,
              child: StatefulBuilder(
                builder: (context, setSheetState) {
                  // Fetch master data once
                  if (isLoading) {
                    Future.wait([
                      FirebaseFirestore.instance.collection('states').get(),
                      FirebaseFirestore.instance.collection('sites').get(),
                      FirebaseFirestore.instance.collection('turbinemodel').get(),
                      FirebaseFirestore.instance.collection('turbinename').get(),
                    ]).then((results) {
                      allStates = results[0].docs.map((doc) => <String, dynamic>{
                        'id': doc.id, 'reference': doc.reference, ...doc.data(),
                      }).toList();
                      allSites = results[1].docs.map((doc) => <String, dynamic>{
                        'id': doc.id, 'reference': doc.reference, ...doc.data(),
                      }).toList();
                      allModels = results[2].docs.map((doc) => <String, dynamic>{
                        'id': doc.id, 'reference': doc.reference, ...doc.data(),
                      }).toList();
                      allTurbines = results[3].docs.map((doc) => <String, dynamic>{
                        'id': doc.id, 'reference': doc.reference, ...doc.data(),
                      }).toList();

                      isLoading = false;

                      // --- Pre-populate from planData ---
                      if (planData['state_ref'] is DocumentReference) {
                        applyStateFilter((planData['state_ref'] as DocumentReference).id, setSheetState);
                      } else if (planData['state'] != null) {
                        final match = allStates.firstWhere((s) => s['state'] == planData['state'], orElse: () => <String, dynamic>{});
                        if (match.isNotEmpty) applyStateFilter(match['id'] as String, setSheetState);
                      }
                      if (planData['site_ref'] is DocumentReference) {
                        applySiteFilter((planData['site_ref'] as DocumentReference).id, setSheetState);
                      }
                      if (planData['turbinemodel_ref'] is DocumentReference) {
                        applyModelFilter((planData['turbinemodel_ref'] as DocumentReference).id, setSheetState);
                      }
                      setSheetState(() {});
                    });
                  }

                  final currentStep = selectedTurbineId != null ? 1 : 0;

                  return Container(
                    constraints: const BoxConstraints(maxWidth: 500),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: IntrinsicHeight(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Header ──
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF00897B), Color(0xFF00695C)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(Icons.wind_power, color: Colors.white, size: 28),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('Start Planned Audit',
                                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                                          const SizedBox(height: 4),
                                          Text(planData['site_name']?.toString() ?? 'Select turbine to begin',
                                            style: const TextStyle(fontSize: 13, color: Colors.white70)),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => Navigator.of(context).pop(),
                                      icon: const Icon(Icons.close, color: Colors.white70),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // ── Body ──
                          if (isLoading)
                            const Padding(
                              padding: EdgeInsets.all(48),
                              child: CircularProgressIndicator(color: Color(0xFF00897B)),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  _buildWizardCard(
                                    stepNumber: 1,
                                    isCompleted: selectedTurbineId != null,
                                    child: SearchableDropdown<String>(
                                      labelText: 'Turbine ID',
                                      hintText: 'Search turbines...',
                                      disabledHint: 'Select Model first',
                                      prefixIcon: Icons.wind_power_outlined,
                                      selectedValue: selectedTurbineId,
                                      enabled: selectedModelId != null,
                                      onChanged: selectedModelId == null ? null : (value) {
                                        setSheetState(() => selectedTurbineId = value);
                                      },
                                      items: () {
                                        final sorted = List<Map<String, dynamic>>.from(visibleTurbines);
                                        sorted.sort((a, b) {
                                          final aHas = turbineDrafts[a['id']] ?? false;
                                          final bHas = turbineDrafts[b['id']] ?? false;
                                          if (aHas && !bHas) return -1;
                                          if (!aHas && bHas) return 1;
                                          return 0;
                                        });
                                        return sorted.map((doc) => SearchableDropdownItem<String>(
                                          value: doc['id'] as String,
                                          label: doc['turbine_name']?.toString() ??
                                              doc['turbine_id']?.toString() ?? 'N/A',
                                          icon: Icons.wind_power,
                                          showRecentIndicator: turbineDrafts[doc['id']] ?? false,
                                        )).toList();
                                      }(),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 56,
                                    child: ElevatedButton(
                                      onPressed: selectedTurbineId == null ? null : () {
                                        Navigator.of(context).pop();
                                        final siteDoc = allSites.firstWhere((d) => d['id'] == selectedSiteId);
                                        final modelDoc = allModels.firstWhere((d) => d['id'] == selectedModelId);
                                        final turbineDoc = allTurbines.firstWhere((d) => d['id'] == selectedTurbineId);
                                        final stateDoc = allStates.firstWhere((d) => d['id'] == selectedStateId);

                                        Navigator.push(
                                          this.context,
                                          MaterialPageRoute<void>(
                                            builder: (_) => AuditMainCategoriesScreen(
                                              siteName: siteDoc['site_name']?.toString() ?? 'Unknown',
                                              turbineName: turbineDoc['turbine_name']?.toString() ?? turbineDoc['turbine_id']?.toString() ?? 'Unknown',
                                              turbineModelRef: modelDoc['reference'] as DocumentReference,
                                              siteRef: siteDoc['reference'] as DocumentReference,
                                              siteId: siteDoc['id'] as String,
                                              turbineId: turbineDoc['id'] as String,
                                              stateName: stateDoc['state']?.toString() ?? 'Unknown',
                                              planId: planId,
                                              planData: planData,
                                            ),
                                          ),
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF00897B),
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor: Colors.grey.shade300,
                                        elevation: selectedTurbineId != null ? 8 : 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(selectedTurbineId != null ? Icons.play_arrow_rounded : Icons.lock_outline),
                                          const SizedBox(width: 8),
                                          Text(
                                            selectedTurbineId != null ? 'Start Audit' : 'Complete Selection',
                                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWizardCard({
    required int stepNumber,
    required bool isCompleted,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isCompleted ? const Color(0xFF00897B).withValues(alpha: 0.3) : Colors.grey.shade200,
              ),
              boxShadow: [
                if (isCompleted)
                  BoxShadow(
                    color: const Color(0xFF00897B).withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
