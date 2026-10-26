import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sticky_header/flutter_sticky_header.dart';
import '../widgets/network_stability_dialog.dart';

/// Pre-submission quality gate screen.
/// Shows a categorized summary of all audit answers,
/// highlighting "Not OK" items with photos, severity, and correction status.
class AuditorSelfReviewScreen extends StatelessWidget {
  final Map<String, Map<String, dynamic>> auditData;
  final VoidCallback onConfirmSubmit;
  final String siteName;
  final String turbineName;
  final int totalTasks;
  final int pendingCount;

  const AuditorSelfReviewScreen({
    required this.auditData,
    required this.onConfirmSubmit,
    required this.siteName,
    required this.turbineName,
    required this.totalTasks,
    required this.pendingCount,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // ── Compute summary counts ──
    var okCount = 0;
    var notOkCount = 0;
    var naCount = 0;
    var correctedCount = 0;

    for (final entry in auditData.values) {
      if (entry['is_corrected'] == true) correctedCount++;

      final status = entry['status'];
      if (status == 'OK') {
        okCount++;
      } else if (status == 'Not OK') {
        notOkCount++;
      } else if (status == 'NA') {
        naCount++;
      }
    }

    // ── Group "Not OK" items by main_category_name ──
    final grouped = <String, List<MapEntry<String, Map<String, dynamic>>>>{};
    for (final entry in auditData.entries) {
      final status = entry.value['status'];
      final isCorrected = entry.value['is_corrected'] == true;
      if (status == 'Not OK' || isCorrected) {
        final categoryName = entry.value['main_category_name']?.toString() ?? 'Uncategorized';
        grouped.putIfAbsent(categoryName, () => []).add(entry);
      }
    }

    // Sort category keys alphabetically
    final sortedCategories = grouped.keys.toList()..sort();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: CustomScrollView(
        slivers: [
          // ── App Bar ──
          SliverAppBar(
            expandedHeight: 140, // Slightly reduced
            pinned: true,
            backgroundColor: const Color(0xFF00897B),
            foregroundColor: Colors.white,
            elevation: 0,
            systemOverlayStyle: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness: Brightness.dark,
            ),
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: false, // Ensure title doesn't crash with back button
              titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
              title: const Text(
                'Review & Submit',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF00897B), Color(0xFF00695C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(56, 16, 16, 50), // Increased bottom padding to avoid title overlap
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          siteName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16, // Slightly smaller
                            fontWeight: FontWeight.w500,
                            fontFamily: 'Outfit',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          turbineName,
                          style: const TextStyle(color: Colors.white60, fontSize: 13, fontFamily: 'Outfit'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Summary Hero Card ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Text(
                      'Audit Summary',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1F36),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Stats Grid (Stable 3 rows to prevent overlap)
                    Column(
                      children: [
                        Row(
                          children: [
                            _buildSummaryPill('TOTAL TASKS', totalTasks, const Color(0xFF1E40AF)), // Deeper blue
                            const SizedBox(width: 12),
                            _buildSummaryPill('OK STATUS', okCount, const Color(0xFF065F46)), // Forest green
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _buildSummaryPill('NOT CONFORM', notOkCount, const Color(0xFF991B1B)), // Deep crimson
                            const SizedBox(width: 12),
                            _buildSummaryPill('OSC (FIXED)', correctedCount, Colors.teal), 
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (pendingCount > 0)
                              _buildSummaryPill('PENDING', pendingCount, Colors.orange.shade800)
                            else
                              _buildSummaryPill('NOT APPLIC.', naCount, Colors.blueGrey.shade700),
                            const SizedBox(width: 12),
                            if (pendingCount > 0)
                               _buildSummaryPill('NOT APPLIC.', naCount, Colors.blueGrey.shade700)
                            else
                               const Spacer(),
                          ],
                        ),
                      ],
                    ),
                    if (correctedCount > 0) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                            const SizedBox(width: 6),
                            Text(
                              '$correctedCount corrected on-spot',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // ── Section Title ──
          if (notOkCount > 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'Non-Conformances ($notOkCount)',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1F36),
                  ),
                ),
              ),
            ),

          // ── Grouped NC Items with Sticky Headers ──
          for (final categoryName in sortedCategories) ...[
            SliverStickyHeader(
              header: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 20,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD32F2F),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        categoryName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1F36),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${grouped[categoryName]!.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD32F2F),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final entry = grouped[categoryName]![index];
                    final taskData = entry.value;
                    return _buildNCCard(taskData);
                  },
                  childCount: grouped[categoryName]!.length,
                ),
              ),
            ),
          ],

          // ── Empty state if no NCs ──
          if (notOkCount == 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade400),
                    const SizedBox(height: 16),
                    const Text(
                      'All Clear!',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No non-conformances found. Ready to submit.',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),

      // ── Confirm & Submit FAB ──
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: pendingCount > 0 
                ? null 
                : () {
                    // Check network stability before popping screen and submitting
                    unawaited(NetworkStabilityDialog.show(
                      context: context,
                      onStabilityConfirmed: () {
                        // Pop this review screen, then trigger submit in parent
                        Navigator.of(context).pop();
                        onConfirmSubmit();
                      },
                    ));
                  },
              icon: Icon(
                pendingCount > 0 ? Icons.lock_outline_rounded : Icons.check_circle_outline, 
                size: 22
              ),
              label: Text(
                pendingCount > 0 
                  ? 'PENDING TASKS: $pendingCount (Complete All)' 
                  : 'Confirm & Submit Audit',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: pendingCount > 0 ? Colors.grey.shade300 : const Color(0xFF00897B),
                foregroundColor: Colors.white,
                elevation: pendingCount > 0 ? 0 : 4,
                shadowColor: const Color(0xFF00897B).withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryPill(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.1), width: 1),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: color,
                  fontFamily: 'Outfit',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: color.withValues(alpha: 0.8),
                  fontFamily: 'Outfit',
                  letterSpacing: 0.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNCCard(Map<String, dynamic> taskData) {
    final title = taskData['question']?.toString() ?? 'Unknown Task';
    final observation = taskData['observation']?.toString() ?? '';
    final subStatus = taskData['sub_status']?.toString();
    final isCorrected = taskData['is_corrected'] == true;
    final photos = (taskData['photos'] as List<dynamic>?) ?? [];
    final subCategoryName = taskData['sub_category_name']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16), // Increased from 8
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.withValues(alpha: 0.05)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // 4px Red left marker
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: isCorrected ? Colors.green : const Color(0xFFD32F2F),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
            ),
            // Photo thumbnail
            if (photos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: _buildPhotoWidget(photos.first.toString()),
                  ),
                ),
              ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (subCategoryName.isNotEmpty)
                      Text(
                        subCategoryName,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1F36),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (observation.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        observation,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Badges
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (subStatus != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getSeverityColor(subStatus).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        subStatus,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _getSeverityColor(subStatus),
                        ),
                      ),
                    ),
                  if (isCorrected) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.green.shade200, width: 0.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, size: 10, color: Colors.green.shade700), // OSC icon
                          const SizedBox(width: 4),
                          Text(
                            'OSC - RESOLVED',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                              fontFamily: 'Outfit',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoWidget(String path) {
    if (path.startsWith('http')) {
      return Image.network(path, fit: BoxFit.cover);
    }
    if (kIsWeb) {
      return Image.network(path, fit: BoxFit.cover);
    }
    return Image.file(File(path), fit: BoxFit.cover);
  }

  Color _getSeverityColor(String severity) {
    switch (severity) {
      case 'CF':
        return const Color(0xFFD32F2F);
      case 'MCF':
        return const Color(0xFF1565C0);
      case 'Aobs':
        return Colors.amber.shade700;
      default:
        return Colors.grey;
    }
  }
}
