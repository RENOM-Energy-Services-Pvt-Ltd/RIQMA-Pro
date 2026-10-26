import 'package:flutter/material.dart';

enum AuditStatusTheme { success, danger, warning, neutral }

class AuditCard extends StatelessWidget {
  final String title;
  final int total;
  final int ok;
  final int notOk;
  final int pending;
  final VoidCallback onTap;
  final VoidCallback? onAddNewNc;

  const AuditCard({
    required this.title,
    required this.total,
    required this.ok,
    required this.notOk,
    required this.pending,
    required this.onTap,
    this.onAddNewNc,
    super.key,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                            height: 1.2,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildIndicatorTag(
                        pending == 0 ? 'COMPLETE' : '${(progress * 100).toInt()}%',
                        color,
                      ),
                    ],
                  ),
                  const Spacer(),
                  
                  // Stats Row - Wide rounded boxes
                  Row(
                    children: [
                      Expanded(child: _buildPillStat('OK', ok, const Color(0xFF059669))),
                      const SizedBox(width: 6),
                      Expanded(child: _buildPillStat('NOK', notOk, const Color(0xFFDC2626))),
                      const SizedBox(width: 6),
                      Expanded(child: _buildPillStat('P', pending, const Color(0xFFD97706))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  
                  // Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: color.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                      minHeight: 5,
                    ),
                  ),
                  if (onAddNewNc != null) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: onAddNewNc,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD32F2F).withValues(alpha: isDark ? 0.2 : 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFD32F2F).withValues(alpha: 0.35),
                            width: 1.0,
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_circle_outline_rounded, size: 13, color: Color(0xFFD32F2F)),
                            SizedBox(width: 4),
                            Text(
                              'Add New NC',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFD32F2F),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
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

class AuditCardSkeleton extends StatefulWidget {
  const AuditCardSkeleton({super.key});

  @override
  State<AuditCardSkeleton> createState() => _AuditCardSkeletonState();
}

class _AuditCardSkeletonState extends State<AuditCardSkeleton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey.shade800 : Colors.grey.shade300;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final shimmerColor = baseColor.withValues(alpha: _animation.value);
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2433) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Title skeleton + Tag skeleton
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          height: 12,
                          decoration: BoxDecoration(
                            color: shimmerColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          width: 80,
                          height: 12,
                          decoration: BoxDecoration(
                            color: shimmerColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 48,
                    height: 18,
                    decoration: BoxDecoration(
                      color: shimmerColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Stats Row (3 pill boxes)
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 28,
                      decoration: BoxDecoration(
                        color: shimmerColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 28,
                      decoration: BoxDecoration(
                        color: shimmerColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 28,
                      decoration: BoxDecoration(
                        color: shimmerColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Progress Bar skeleton
              Container(
                width: double.infinity,
                height: 6,
                decoration: BoxDecoration(
                  color: shimmerColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
