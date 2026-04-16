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
        var totalPlanned = 0;
        
        if (planningSnapshot.hasData) {
          for (var doc in planningSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            // Filter for approved/completed audits only
            final status = data['status'] ?? 'pending_approval';
            if (['approved', 'Planned', 'completed'].contains(status)) {
              validPlanningDocs.add(doc);
              final count = (data['number_of_turbines'] ?? 1) as int;
              totalPlanned += count;
            }
          }
        }

        Query auditQuery = FirebaseFirestore.instance
              .collection('audit_submissions')
              .where('admin_status', isEqualTo: 'Approved')
              .orderBy('timestamp', descending: true);

        if (assignedState != null && assignedState!.isNotEmpty) {
          // Apply .trim() to prevent whitespace issues
          auditQuery = auditQuery.where('state', isEqualTo: assignedState!.trim());
          debugPrint('📊 HomeTab: Filtering audits by state: ${assignedState!.trim()}');
        }

        return StreamBuilder<QuerySnapshot>(
          stream: auditQuery.snapshots(),
          builder: (context, auditSnapshot) {
            if (auditSnapshot.hasError) {
              return Center(child: Text('Error: ${auditSnapshot.error}'));
            }

            final actual = auditSnapshot.hasData ? auditSnapshot.data!.docs.length : 0;
            final completionRate = totalPlanned > 0 ? (actual / totalPlanned * 100).toInt() : 0;

            final recentAudits = auditSnapshot.hasData 
                ? auditSnapshot.data!.docs.take(5).toList() 
                : <QueryDocumentSnapshot<Object?>>[];

            // Calculate site performance
            final sitePerformance = _calculateSitePerformance(
              validPlanningDocs,
              auditSnapshot.data?.docs ?? [],
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
                  
                  // Recent Activity Section
                  const Text(
                    'Recent Activity',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (recentAudits.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Text(
                          'No recent activity',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ...recentAudits.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final site = (data['site'] as String?) ?? 'Unknown Site';
                      final turbine = (data['turbine'] as String?) ?? 'Unknown';
                      final timestamp = data['timestamp'] as Timestamp?;
                      final dateStr = timestamp != null
                          ? DateFormat('dd MMM yyyy').format(timestamp.toDate())
                          : 'No date';
                      
                      return _buildRecentActivityItem(
                        title: '$site - $turbine',
                        date: dateStr,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (context) => AuditDetailsScreen(
                                auditData: data['audit_data'] != null
                                    ? Map<String, dynamic>.from(data['audit_data'] as Map)
                                    : {},
                                siteName: site,
                                turbineName: turbine,
                                timestamp: timestamp,
                              ),
                            ),
                          );
                        },
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
      final siteName = (data['site'] as String?) ?? 'Unknown Site';
      
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

  Widget _buildRecentActivityItem({
    required String title,
    required String date,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        onTap: onTap,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(date),
        trailing: const Icon(Icons.visibility_outlined, color: Colors.grey),
      ),
    );
  }
}
