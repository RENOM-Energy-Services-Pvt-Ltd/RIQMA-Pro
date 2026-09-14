import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/audit_details_screen.dart';

class HomeTab extends StatelessWidget {
  final String? assignedState;

  const HomeTab({super.key, this.assignedState});

  @override
  Widget build(BuildContext context) {
    Query planningQuery = FirebaseFirestore.instance.collection('planning_data');
    if (assignedState != null && assignedState!.isNotEmpty) {
      // Apply .trim() to prevent whitespace issues
      planningQuery = planningQuery.where('state', isEqualTo: assignedState!.trim());
      debugPrint('📊 HomeTab: Filtering planning by state: ${assignedState!.trim()}');
    }

    return StreamBuilder<QuerySnapshot>(
      stream: planningQuery.snapshots(),
      builder: (context, planningSnapshot) {
        if (planningSnapshot.hasError) {
          return Center(child: Text('Error: ${planningSnapshot.error}'));
        }

        final validPlanningDocs = <QueryDocumentSnapshot>[];
        final plannedAuditIds = <String>{};
        final completedPlansByAuditId = <String, Map<String, dynamic>>{};
        var totalPlanned = 0;
        
        if (planningSnapshot.hasData) {
          for (var doc in planningSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final status = (data['status'] as String?)?.toLowerCase() ?? 'pending_approval';
            if (['approved', 'planned', 'completed'].contains(status)) {
              validPlanningDocs.add(doc);
              final count = (data['number_of_turbines'] ?? 1) as int;
              totalPlanned += count;
            }

            final linkedAuditId = data['linked_audit_id']?.toString().trim();
            if (linkedAuditId != null && linkedAuditId.isNotEmpty) {
              plannedAuditIds.add(linkedAuditId);
              completedPlansByAuditId[linkedAuditId] = data;
            }
          }
        }

        // Fetch audit submissions without composite-index constraints
        final auditStream = FirebaseFirestore.instance
            .collection('audit_submissions')
            .snapshots();

        return StreamBuilder<QuerySnapshot>(
          stream: auditStream,
          builder: (context, auditSnapshot) {
            if (auditSnapshot.hasError) {
              debugPrint('❌ HomeTab: Error loading audit submissions: ${auditSnapshot.error}');
              return Center(child: Text('Error: ${auditSnapshot.error}'));
            }

            final allAuditDocs = auditSnapshot.hasData
                ? auditSnapshot.data!.docs
                : <QueryDocumentSnapshot>[];

            // Filter for ONLY audits that were planned, completed, and approved by manager review
            final actualApprovedAudits = allAuditDocs.where((doc) {
              return _isPlannedAndManagerApproved(
                doc,
                plannedAuditIds,
                completedPlansByAuditId,
                assignedState,
              );
            }).toList()
              ..sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;
                final tA = (aData['timestamp'] as Timestamp?)?.toDate();
                final tB = (bData['timestamp'] as Timestamp?)?.toDate();
                if (tA == null && tB == null) return 0;
                if (tA == null) return 1;
                if (tB == null) return -1;
                return tB.compareTo(tA);
              });

            final actual = actualApprovedAudits.length;
            final completionRate = totalPlanned > 0 ? (actual / totalPlanned * 100).toInt() : 0;

            // Filter for Approved Audits strictly in the Current Financial Year (FY)
            final currentFyApprovedAudits = allAuditDocs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final isApproved = _isApprovedAfterManagerReview(
                doc,
                completedPlansByAuditId,
                assignedState,
              );
              final isCurrentFy = isAuditInCurrentFY(data);
              return isApproved && isCurrentFy;
            }).toList()
              ..sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;
                final tA = getAuditDate(aData);
                final tB = getAuditDate(bData);
                if (tA == null && tB == null) return 0;
                if (tA == null) return 1;
                if (tB == null) return -1;
                return tB.compareTo(tA);
              });

            // Calculate site performance based strictly on approved planned audits
            final sitePerformance = _calculateSitePerformance(
              validPlanningDocs,
              actualApprovedAudits,
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Dashboard Overview',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Metrics Cards
                  _buildMetricCard(
                    context: context,
                    title: 'Total Planned',
                    value: '$totalPlanned',
                    icon: Icons.assignment_outlined,
                    iconColor: Colors.lightBlue,
                  ),
                  const SizedBox(height: 16),
                  _buildMetricCard(
                    context: context,
                    title: 'Actual',
                    value: '$actual',
                    icon: Icons.check_circle_outline,
                    iconColor: Colors.lightGreen,
                  ),
                  const SizedBox(height: 16),
                  _buildMetricCard(
                    context: context,
                    title: 'Completion Rate',
                    value: '$completionRate%',
                    icon: Icons.pie_chart_outline,
                    iconColor: Colors.blue,
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Site Performance Section
                  const Text(
                    'Site Performance',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...sitePerformance.entries.map((entry) {
                    final siteName = entry.key;
                    final data = entry.value;
                    final completed = data['completed'] as int;
                    final total = data['total'] as int;
                    final percentage = total > 0 ? completed / total : 0.0;
                    
                    return _buildSitePerformanceRow(
                      context: context,
                      siteName: siteName,
                      completed: completed,
                      total: total,
                      percentage: percentage,
                    );
                  }),
                  
                  const SizedBox(height: 32),
                  
                  // Recent Activity Section (Audit-Wise NC Points for Current FY)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recent Activity',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_month_outlined,
                              size: 13,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              getCurrentFinancialYearLabel(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Approved audits and NC points for ${getCurrentFinancialYearLabel()}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (currentFyApprovedAudits.isEmpty)
                    Card(
                      elevation: 0,
                      color: Colors.grey.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.assignment_turned_in_outlined, size: 40, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                'No approved audits found for ${getCurrentFinancialYearLabel()}',
                                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Approved audits and their NC points will appear here once reviewed by the manager.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    ...currentFyApprovedAudits.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final site = (data['site'] as String?) ?? (data['site_name'] as String?) ?? 'Unknown Site';
                      final turbine = (data['turbine'] as String?) ?? (data['turbine_id'] as String?) ?? 'Unknown Turbine';
                      final timestamp = data['timestamp'] as Timestamp?;
                      final auditDate = getAuditDate(data);
                      final dateStr = auditDate != null
                          ? DateFormat('dd MMM yyyy').format(auditDate)
                          : 'No date';
                      final ncPoints = _extractNcPoints(data);

                      return _buildAuditCard(
                        context: context,
                        doc: doc,
                        site: site,
                        turbine: turbine,
                        dateStr: dateStr,
                        timestamp: timestamp,
                        auditData: data['audit_data'] != null
                            ? Map<String, dynamic>.from(data['audit_data'] as Map)
                            : {},
                        ncPoints: ncPoints,
                      );
                    }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool _isPlannedAndManagerApproved(
    QueryDocumentSnapshot doc,
    Set<String> plannedAuditIds,
    Map<String, Map<String, dynamic>> completedPlansByAuditId,
    String? assignedState,
  ) {
    final data = doc.data() as Map<String, dynamic>;

    // 1. State Filter
    if (assignedState != null && assignedState.trim().isNotEmpty) {
      final targetState = assignedState.trim().toLowerCase();
      final docState = (data['state'] ?? data['state_name'] ?? '').toString().trim().toLowerCase();
      if (docState.isNotEmpty && docState != targetState) {
        return false;
      }
    }

    // 2. Must be a Planned Audit ("jo audit planned the")
    // Check if explicitly marked unplanned
    if (data['is_unplanned'] == true || data['plan_id'] == 'unplanned') {
      return false;
    }

    final planId = data['plan_id']?.toString().trim();
    final hasValidPlanId = planId != null && planId.isNotEmpty && planId != 'unplanned';
    final isMarkedPlanned = data['is_planned'] == true;
    final isLinkedToPlan = plannedAuditIds.contains(doc.id);

    if (!hasValidPlanId && !isMarkedPlanned && !isLinkedToPlan) {
      return false;
    }

    // 3. Must be Completed and Approved After Manager Review ("complete hokar manager reveiw ke bad approved ho gye h")
    final adminStatus = data['admin_status']?.toString().trim().toLowerCase();
    final managerStatus = data['manager_status']?.toString().trim().toLowerCase();
    final reviewStatus = data['manager_review_status']?.toString().trim().toLowerCase();
    final docStatus = data['status']?.toString().trim().toLowerCase();

    // Check direct approval flags on audit_submissions document
    if (adminStatus == 'approved' ||
        managerStatus == 'approved' ||
        reviewStatus == 'approved' ||
        docStatus == 'approved' ||
        docStatus == 'manager_approved' ||
        docStatus == 'completed_approved') {
      return true;
    }

    // Check if the linked plan in planning_data has manager approval recorded
    final linkedPlan = completedPlansByAuditId[doc.id];
    if (linkedPlan != null) {
      final planAdminStatus = linkedPlan['admin_status']?.toString().trim().toLowerCase();
      final planManagerStatus = linkedPlan['manager_status']?.toString().trim().toLowerCase();
      final planStatus = linkedPlan['status']?.toString().trim().toLowerCase();
      if (planAdminStatus == 'approved' || planManagerStatus == 'approved') {
        return true;
      }
      if (planStatus == 'approved') {
        return true;
      }
    }

    // Check task-level manager feedback in audit_data
    final auditData = data['audit_data'];
    if (auditData is Map && auditData.isNotEmpty) {
      var hasManagerDecision = false;
      var allDecisionsApproved = true;

      for (var taskEntry in auditData.values) {
        if (taskEntry is Map) {
          final tAdminStatus = taskEntry['admin_status']?.toString().trim().toLowerCase();
          if (tAdminStatus != null && tAdminStatus.isNotEmpty) {
            hasManagerDecision = true;
            if (tAdminStatus != 'approved') {
              allDecisionsApproved = false;
            }
          }
        }
      }

      if (hasManagerDecision && allDecisionsApproved) {
        return true;
      }
    }

    return false;
  }

  Map<String, Map<String, int>> _calculateSitePerformance(
    List<QueryDocumentSnapshot> planningDocs,
    List<QueryDocumentSnapshot> auditDocs,
  ) {
    final siteData = <String, Map<String, int>>{};

    // Count planned per site
    for (var doc in planningDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final siteName = (data['site_name'] as String?) ?? 'Unknown Site';
      final count = (data['number_of_turbines'] ?? 1) as int;
      
      if (!siteData.containsKey(siteName)) {
        siteData[siteName] = {'total': 0, 'completed': 0};
      }
      siteData[siteName]!['total'] = siteData[siteName]!['total']! + count;
    }

    // Count completed per site
    for (var doc in auditDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final siteName = (data['site'] as String?) ?? (data['site_name'] as String?) ?? 'Unknown Site';
      
      if (siteData.containsKey(siteName)) {
        siteData[siteName]!['completed'] = siteData[siteName]!['completed']! + 1;
      }
    }

    return siteData;
  }

  Widget _buildMetricCard({
    required BuildContext context,
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 32),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSitePerformanceRow({
    required BuildContext context,
    required String siteName,
    required int completed,
    required int total,
    required double percentage,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  siteName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$completed/$total Completed',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: percentage,
              color: Theme.of(context).colorScheme.primary,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== FINANCIAL YEAR & AUDIT HELPERS ====================

  /// Checks whether a given [DateTime] falls within the current Indian Financial Year (1 April - 31 March).
  static bool isCurrentFinancialYear(DateTime date) {
    final now = DateTime.now();
    final currentFyStartYear = now.month >= 4 ? now.year : now.year - 1;
    final fyStart = DateTime(currentFyStartYear, 4, 1, 0, 0, 0);
    final fyEnd = DateTime(currentFyStartYear + 1, 3, 31, 23, 59, 59, 999);
    return (date.isAfter(fyStart) || date.isAtSameMomentAs(fyStart)) &&
           (date.isBefore(fyEnd) || date.isAtSameMomentAs(fyEnd));
  }

  /// Returns the current Financial Year string, e.g. "FY 2026-27".
  static String getCurrentFinancialYearLabel([DateTime? referenceDate]) {
    final now = referenceDate ?? DateTime.now();
    final startYear = now.month >= 4 ? now.year : now.year - 1;
    final endYearShort = ((startYear + 1) % 100).toString().padLeft(2, '0');
    return 'FY $startYear-$endYearShort';
  }

  /// Extracts the date from an audit submission document.
  static DateTime? getAuditDate(Map<String, dynamic> data) {
    if (data['timestamp'] is Timestamp) {
      return (data['timestamp'] as Timestamp).toDate();
    }
    if (data['actual_date_maintenance'] is Timestamp) {
      return (data['actual_date_maintenance'] as Timestamp).toDate();
    }
    if (data['completed_at'] is Timestamp) {
      return (data['completed_at'] as Timestamp).toDate();
    }
    if (data['created_at'] is Timestamp) {
      return (data['created_at'] as Timestamp).toDate();
    }
    return null;
  }

  /// Checks if audit data belongs to the current FY.
  static bool isAuditInCurrentFY(Map<String, dynamic> data) {
    // Check if doc has an explicit FY field
    final rawFy = (data['financial_year'] ?? data['fy'])?.toString().trim();
    if (rawFy != null && rawFy.isNotEmpty) {
      final now = DateTime.now();
      final startYear = now.month >= 4 ? now.year : now.year - 1;
      final endYear = startYear + 1;
      final endYearShort = (endYear % 100).toString().padLeft(2, '0');

      final allowedFormats = {
        'FY $startYear-$endYearShort'.toUpperCase(),
        'FY $startYear-$endYear'.toUpperCase(),
        '$startYear-$endYearShort'.toUpperCase(),
        '$startYear-$endYear'.toUpperCase(),
        'FY$startYear-$endYearShort'.toUpperCase(),
        'FY$startYear$endYearShort'.toUpperCase(),
      };

      if (allowedFormats.contains(rawFy.toUpperCase())) {
        return true;
      }
      return false;
    }

    // Otherwise derive from timestamp
    final auditDate = getAuditDate(data);
    if (auditDate != null) {
      return isCurrentFinancialYear(auditDate);
    }

    // Default to true if no date field present
    return true;
  }

  /// Determines if an audit is completed and approved after manager review.
  bool _isApprovedAfterManagerReview(
    QueryDocumentSnapshot doc,
    Map<String, Map<String, dynamic>> completedPlansByAuditId,
    String? assignedState,
  ) {
    final data = doc.data() as Map<String, dynamic>;

    // 1. State Filter
    if (assignedState != null && assignedState.trim().isNotEmpty) {
      final targetState = assignedState.trim().toLowerCase();
      final docState = (data['state'] ?? data['state_name'] ?? '').toString().trim().toLowerCase();
      if (docState.isNotEmpty && docState != targetState) {
        return false;
      }
    }

    // 2. Direct approval flags on audit_submissions document
    final adminStatus = data['admin_status']?.toString().trim().toLowerCase();
    final managerStatus = data['manager_status']?.toString().trim().toLowerCase();
    final reviewStatus = data['manager_review_status']?.toString().trim().toLowerCase();
    final docStatus = data['status']?.toString().trim().toLowerCase();

    if (adminStatus == 'approved' ||
        managerStatus == 'approved' ||
        reviewStatus == 'approved' ||
        docStatus == 'approved' ||
        docStatus == 'manager_approved' ||
        docStatus == 'completed_approved') {
      return true;
    }

    // 3. Linked plan approval in planning_data
    final linkedPlan = completedPlansByAuditId[doc.id];
    if (linkedPlan != null) {
      final planAdminStatus = linkedPlan['admin_status']?.toString().trim().toLowerCase();
      final planManagerStatus = linkedPlan['manager_status']?.toString().trim().toLowerCase();
      final planStatus = linkedPlan['status']?.toString().trim().toLowerCase();
      if (planAdminStatus == 'approved' ||
          planManagerStatus == 'approved' ||
          planStatus == 'approved') {
        return true;
      }
    }

    // 4. Task-level manager review in audit_data
    final auditData = data['audit_data'];
    if (auditData is Map && auditData.isNotEmpty) {
      var hasManagerDecision = false;
      var allDecisionsApproved = true;

      for (var taskEntry in auditData.values) {
        if (taskEntry is Map) {
          final tAdminStatus = taskEntry['admin_status']?.toString().trim().toLowerCase();
          if (tAdminStatus != null && tAdminStatus.isNotEmpty) {
            hasManagerDecision = true;
            if (tAdminStatus != 'approved') {
              allDecisionsApproved = false;
            }
          }
        }
      }

      if (hasManagerDecision && allDecisionsApproved) {
        return true;
      }
    }

    return false;
  }

  /// Extracts all Not OK (NC) points from an audit's audit_data.
  List<Map<String, dynamic>> _extractNcPoints(Map<String, dynamic> auditDocData) {
    final ncList = <Map<String, dynamic>>[];
    final auditData = auditDocData['audit_data'];
    if (auditData is! Map) return ncList;

    for (var entry in auditData.entries) {
      if (entry.value is Map) {
        final task = Map<String, dynamic>.from(entry.value as Map);
        final status = task['status']?.toString().trim().toLowerCase();

        // Check if task is marked Not OK
        if (status == 'not ok') {
          final photoList = <String>[];

          // 1. Photos array
          if (task['photos'] is List) {
            for (var p in task['photos'] as List) {
              final url = p?.toString().trim() ?? '';
              if (url.isNotEmpty && !photoList.contains(url)) {
                photoList.add(url);
              }
            }
          }

          // 2. Closure / OSC Photo
          final closurePhoto = task['closure_photo']?.toString().trim() ?? '';
          if (closurePhoto.isNotEmpty && !photoList.contains(closurePhoto)) {
            photoList.add(closurePhoto);
          }

          // 3. Evidence photo URL
          final evidenceUrl = task['evidence_photo_url']?.toString().trim() ?? '';
          if (evidenceUrl.isNotEmpty && !photoList.contains(evidenceUrl)) {
            photoList.add(evidenceUrl);
          }

          task['taskId'] = entry.key;
          task['collected_photos'] = photoList;
          ncList.add(task);
        }
      }
    }

    return ncList;
  }

  // ==================== UI BUILDERS FOR AUDIT & NC POINTS ====================

  Widget _buildAuditCard({
    required BuildContext context,
    required QueryDocumentSnapshot doc,
    required String site,
    required String turbine,
    required String dateStr,
    required Timestamp? timestamp,
    required Map<String, dynamic> auditData,
    required List<Map<String, dynamic>> ncPoints,
  }) {
    final hasNc = ncPoints.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasNc ? Colors.red.shade200 : Colors.green.shade200,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Site - Turbine, Date, and Badges
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.wind_power,
                    color: Theme.of(context).colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$site - $turbine',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 12, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Text(
                        'Approved',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: hasNc ? Colors.red.shade50 : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: hasNc ? Colors.red.shade200 : Colors.green.shade200,
                        ),
                      ),
                      child: Text(
                        hasNc
                            ? '${ncPoints.length} NC Point${ncPoints.length > 1 ? 's' : ''}'
                            : 'All OK (0 NC)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: hasNc ? Colors.red.shade700 : Colors.green.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // NC Points List
            if (hasNc) ...[
              Text(
                'Non-Conformance Points:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade900,
                ),
              ),
              const SizedBox(height: 8),
              ...ncPoints.asMap().entries.map((entry) {
                final index = entry.key;
                final nc = entry.value;
                return _buildNcPointItem(context, nc, index);
              }),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: Colors.green.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No non-conformance points found. This audit is 100% compliant.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.green.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),
            // Footer: View Full Audit Details Button
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => AuditDetailsScreen(
                        auditData: auditData,
                        siteName: site,
                        turbineName: turbine,
                        timestamp: timestamp,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text(
                  'View Full Audit Details',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNcPointItem(BuildContext context, Map<String, dynamic> nc, int index) {
    final question = (nc['question'] ?? nc['title'] ?? 'Non-Conformance Item').toString();
    final subCategory = (nc['sub_category_name'] ?? nc['main_category_name'] ?? '').toString();
    final observation = (nc['observation'] ?? '').toString().trim();
    final remarks = (nc['remarks'] ?? '').toString().trim();
    final photos = (nc['collected_photos'] as List<String>?) ?? [];
    final isCorrected = nc['is_corrected'] == true;
    final closureRemark = (nc['closure_remark'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey.shade900
            : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: Colors.red.shade600, width: 3.5),
          top: BorderSide(color: Colors.grey.shade300),
          right: BorderSide(color: Colors.grey.shade300),
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: NC Index, Question, Status badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  'NC #${index + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  question,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Text(
                  'Not OK',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
              ),
            ],
          ),

          // Subcategory Info
          if (subCategory.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 13,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  subCategory,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],

          // Auditor Observation
          if (observation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Observation:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    observation,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ],

          // Auditor Remarks
          if (remarks.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Remarks: ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  TextSpan(
                    text: remarks,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],

          // On-the-spot Correction
          if (isCorrected) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 14, color: Colors.green.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      closureRemark.isNotEmpty
                          ? 'Resolved on-the-spot: $closureRemark'
                          : 'Resolved on-the-spot',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Photos gallery with tap to zoom
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.photo_library_outlined, size: 13, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  'Photos (${photos.length}) - Tap to enlarge',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (context, idx) => const SizedBox(width: 8),
                itemBuilder: (context, photoIndex) {
                  final photoUrl = photos[photoIndex];
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (context) => PhotoViewerScreen(
                            photos: photos,
                            initialIndex: photoIndex,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                        color: Colors.grey.shade100,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildPhotoImage(photoUrl),
                            Positioned(
                              right: 4,
                              bottom: 4,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(
                                  Icons.zoom_in,
                                  size: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhotoImage(String photoUrl) {
    if (photoUrl.startsWith('http://') || photoUrl.startsWith('https://')) {
      return Image.network(
        photoUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey.shade200,
            child: const Center(
              child: Icon(Icons.broken_image, size: 22, color: Colors.grey),
            ),
          );
        },
      );
    } else {
      return Container(
        color: Colors.grey.shade200,
        child: const Center(
          child: Icon(Icons.image, size: 22, color: Colors.grey),
        ),
      );
    }
  }
}
