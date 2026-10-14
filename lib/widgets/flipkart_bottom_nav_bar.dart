import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Navigation item model for [FlipkartBottomNavBar].
class FlipkartNavItem {
  final IconData icon;
  final String label;
  final IconData? activeIcon;

  const FlipkartNavItem({
    required this.icon,
    required this.label,
    this.activeIcon,
  });
}

/// An iOS-inspired floating frosted glass bottom navigation bar with an
/// intelligent, horizontally draggable animated indicator capsule and an iPhone
/// Home Indicator bar.
///
/// Features:
/// - Real Frosted Glassmorphism with BackdropFilter blur and specular border.
/// - Adaptive indicator pill that dynamically sizes to fit all label lengths without clipping.
/// - FittedBox text scaling to guarantee text never overflows the glass capsule.
/// - Draggable with spring physics & haptic feedback across tabs.
/// - Authentic iPhone Home Indicator horizontal line centered at the bottom.
class FlipkartBottomNavBar extends StatefulWidget {
  final List<FlipkartNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? indicatorColor;
  final Color? backgroundColor;
  final double height;
  final bool showHomeIndicator;

  const FlipkartBottomNavBar({
    required this.items,
    required this.currentIndex,
    required this.onTap,
    super.key,
    this.activeColor,
    this.inactiveColor,
    this.indicatorColor,
    this.backgroundColor,
    this.height = 64.0,
    this.showHomeIndicator = true,
  }) : assert(items.length >= 2, 'FlipkartBottomNavBar requires at least 2 items');

  @override
  State<FlipkartBottomNavBar> createState() => _FlipkartBottomNavBarState();
}

class _FlipkartBottomNavBarState extends State<FlipkartBottomNavBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _animation;

  // Continuous indicator position [0.0 ... items.length - 1]
  double _currentProgress = 0.0;
  bool _isDragging = false;
  int _lastHapticIndex = -1;

  @override
  void initState() {
    super.initState();
    _currentProgress = widget.currentIndex.toDouble();
    _lastHapticIndex = widget.currentIndex;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _animation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );

    _animController.addListener(() {
      if (!_isDragging) {
        setState(() {
          _currentProgress = _animation.value;
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant FlipkartBottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex && !_isDragging) {
      _animateTo(widget.currentIndex.toDouble());
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _animateTo(double targetValue) {
    _animController
      ..stop()
      ..reset();
    _animation = Tween<double>(
      begin: _currentProgress,
      end: targetValue,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
      ),
    );
    _animController.forward();
  }

  void _updateProgressFromDx(double dx, double totalWidth) {
    final tabWidth = totalWidth / widget.items.length;
    final progress = (dx - (tabWidth / 2)) / tabWidth;
    final clamped = progress.clamp(0.0, (widget.items.length - 1).toDouble());

    final nearestIndex = clamped.round();
    if (nearestIndex != _lastHapticIndex) {
      _lastHapticIndex = nearestIndex;
      HapticFeedback.selectionClick();
    }

    setState(() {
      _currentProgress = clamped;
    });
  }

  void _onHorizontalDragStart(DragStartDetails details, double totalWidth) {
    _animController.stop();
    setState(() {
      _isDragging = true;
    });
    _updateProgressFromDx(details.localPosition.dx, totalWidth);
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details, double totalWidth) {
    _updateProgressFromDx(details.localPosition.dx, totalWidth);
  }

  void _onHorizontalDragEnd(DragEndDetails details, double totalWidth) {
    setState(() {
      _isDragging = false;
    });

    final velocity = details.primaryVelocity ?? 0.0;
    final velocityBonus = (velocity / 1200.0).clamp(-0.8, 0.8);
    final projected = _currentProgress + velocityBonus;
    final targetIndex = projected.round().clamp(0, widget.items.length - 1);

    HapticFeedback.lightImpact();
    _animateTo(targetIndex.toDouble());

    if (targetIndex != widget.currentIndex) {
      widget.onTap(targetIndex);
    }
  }

  void _onHorizontalDragCancel() {
    setState(() {
      _isDragging = false;
    });
    _animateTo(widget.currentIndex.toDouble());
  }

  void _onTapUp(TapUpDetails details, double totalWidth) {
    final tabWidth = totalWidth / widget.items.length;
    final targetIndex =
        (details.localPosition.dx / tabWidth).floor().clamp(0, widget.items.length - 1);

    HapticFeedback.selectionClick();
    _animateTo(targetIndex.toDouble());

    if (targetIndex != widget.currentIndex) {
      widget.onTap(targetIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = widget.backgroundColor ??
        (isDark ? const Color(0xFF1E2126) : Colors.white);

    // Renom Teal default active color
    final activeColor = widget.activeColor ?? const Color(0xFF00897B);

    final inactiveColor = widget.inactiveColor ??
        (isDark ? const Color(0xFF9EA3AE) : const Color(0xFF6B7280));

    final indicatorColor = widget.indicatorColor ??
        (isDark
            ? const Color(0xFF00897B).withValues(alpha: 0.28)
            : const Color(0xFF00897B).withValues(alpha: 0.12));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Frosted Glass Floating Dock
        LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            final count = widget.items.length;
            final tabWidth = totalWidth / count;

            // Spatially optimized capsule: leaves 5px on each side of the tab
            const indicatorPaddingH = 5.0;
            final indicatorWidth = tabWidth - (indicatorPaddingH * 2);
            final indicatorHeight = widget.height - 10.0;

            // Horizontal position of the sliding indicator
            final indicatorLeft =
                (_currentProgress * tabWidth) + indicatorPaddingH;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) => _onHorizontalDragStart(d, totalWidth),
              onHorizontalDragUpdate: (d) => _onHorizontalDragUpdate(d, totalWidth),
              onHorizontalDragEnd: (d) => _onHorizontalDragEnd(d, totalWidth),
              onHorizontalDragCancel: _onHorizontalDragCancel,
              onTapUp: (d) => _onTapUp(d, totalWidth),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.height / 2),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: Container(
                    height: widget.height,
                    decoration: BoxDecoration(
                      color: bgColor.withValues(alpha: isDark ? 0.82 : 0.88),
                      borderRadius: BorderRadius.circular(widget.height / 2),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.8),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? const Color(0x66000000)
                              : const Color(0x18000000),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                          spreadRadius: 0,
                        ),
                        BoxShadow(
                          color: isDark
                              ? const Color(0x33000000)
                              : const Color(0x0A000000),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        // Sliding Smart Glass Capsule
                        Positioned(
                          left: indicatorLeft,
                          top: (widget.height - indicatorHeight) / 2,
                          width: indicatorWidth,
                          height: indicatorHeight,
                          child: AnimatedScale(
                            scale: _isDragging ? 1.04 : 1.0,
                            duration: const Duration(milliseconds: 120),
                            curve: Curves.easeOut,
                            child: Container(
                              decoration: BoxDecoration(
                                color: indicatorColor,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF00897B).withValues(alpha: 0.35)
                                      : const Color(0xFF00897B).withValues(alpha: 0.22),
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF00897B).withValues(
                                      alpha: _isDragging ? 0.25 : 0.10,
                                    ),
                                    blurRadius: _isDragging ? 12 : 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Tab Items Layer
                        Row(
                          children: List.generate(count, (index) {
                            final item = widget.items[index];
                            final distance = (_currentProgress - index).abs();
                            final proximity = (1.0 - distance).clamp(0.0, 1.0);

                            final itemColor = Color.lerp(
                              inactiveColor,
                              activeColor,
                              proximity,
                            )!;

                            final scale = 1.0 + (0.05 * proximity);
                            final isSelected = index == widget.currentIndex;

                            return Expanded(
                              child: Transform.scale(
                                scale: scale,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        (proximity > 0.6 && item.activeIcon != null)
                                            ? item.activeIcon
                                            : item.icon,
                                        size: 22,
                                        color: itemColor,
                                      ),
                                      const SizedBox(height: 2),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                          child: Text(
                                            item.label,
                                            maxLines: 1,
                                            softWrap: false,
                                            style: TextStyle(
                                              fontSize: 11.0,
                                              fontWeight: isSelected
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: itemColor,
                                              letterSpacing: -0.2,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),

        // 2. iPhone Home Indicator Bar (Centered at Bottom)
        if (widget.showHomeIndicator) ...[
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 136,
              height: 4.5,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.35)
                    : Colors.black.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
          const SizedBox(height: 2),
        ],
      ],
    );
  }
}
