import 'package:flutter/material.dart';

enum AuditStatusTheme { success, danger, warning, neutral }

class AuditCard extends StatelessWidget {
  final String title;
  final int total;
  final int ok;
  final int notOk;
  final int pending;
  final VoidCallback onTap;

  const AuditCard({
    required this.title, required this.total, required this.ok, required this.notOk, required this.pending, required this.onTap, super.key,
  });

  AuditStatusTheme get _theme {
    if (notOk > 0) return AuditStatusTheme.danger;
    if (total > 0 && pending == 0 && notOk == 0) return AuditStatusTheme.success;
    if (pending < total && pending > 0) return AuditStatusTheme.warning;
    return AuditStatusTheme.neutral;
  }

  Color get _baseColor {
    switch (_theme) {
      case AuditStatusTheme.success:
        return const Color(0xFF10B981);
      case AuditStatusTheme.danger:
        return const Color(0xFFEF4444);
      case AuditStatusTheme.warning:
        return const Color(0xFFF59E0B);
      case AuditStatusTheme.neutral:
        return const Color(0xFF6366F1);
    }
  }

  IconData get _icon {
    switch (_theme) {
      case AuditStatusTheme.success:
        return Icons.check_circle_outline_rounded;
      case AuditStatusTheme.danger:
        return Icons.error_outline_rounded;
      case AuditStatusTheme.warning:
        return Icons.pending_actions_rounded;
      case AuditStatusTheme.neutral:
        return Icons.assignment_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _baseColor;
    final progress = total > 0 ? (total - pending) / total : 0.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: isDark ? 0.3 : 0.6), width: 2.5),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: isDark ? 0.02 : 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Background Gradient Fill
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(alpha: isDark ? 0.02 : 0.04),
                      color.withValues(alpha: isDark ? 0.06 : 0.12),
                    ],
                  ),
                ),
              ),
            ),
            
            // Content
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(_icon, color: color, size: 24), // Reduced from 34
                       _buildIndicatorTag(pending == 0 ? 'COMPLETE' : '${(progress * 100).toInt()}%', color),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15, // Reduced from 19
                      fontWeight: FontWeight.bold, // Switched from w900 for sharper look
                      color: Theme.of(context).colorScheme.onSurface,
                      height: 1.1,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  
                  // Stats Row - Wide rounded boxes
                  Row(
                    children: [
                      Expanded(child: _buildPillStat('OK', ok, const Color(0xFF059669))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildPillStat('NOK', notOk, const Color(0xFFDC2626))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildPillStat('P', pending, const Color(0xFFD97706))),
                    ],
                  ),
                  const SizedBox(height: 14),
                  
                  // Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: color.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      minHeight: 6, // Slimmer bar
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicatorTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), // Reduced padding
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color), // Reduced font size
      ),
    );
  }

  Widget _buildPillStat(String label, int count, Color statColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4), // Reduced from 8
      decoration: BoxDecoration(
        color: statColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statColor.withValues(alpha: 0.3), width: 1.0), // Thinner border
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9, // Reduced from 11
              fontWeight: FontWeight.bold, // Switched from w900
              color: statColor.withValues(alpha: 0.8),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12, // Reduced from 15
              fontWeight: FontWeight.bold, // Switched from w900
              color: statColor,
            ),
          ),
        ],
      ),
    );
  }
}
