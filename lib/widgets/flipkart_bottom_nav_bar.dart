import 'dart:math' as math;
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

/// A Flipkart-inspired floating bottom navigation bar with a horizontally
/// draggable, animated indicator pill.
///
/// Features:
/// - Floating capsule/pill shape with soft elevation and crisp border.
/// - The grey active indicator pill can be dragged horizontally across tabs.
/// - While dragging, the indicator follows finger movement smoothly in real time.
/// - Upon release (drop), it smoothly snaps to the nearest tab with ease-out cubic animation
///   and activates that tab with haptic feedback.
/// - Tapping any tab directly glides the indicator smoothly to that tab.
/// - Fluid color and scale transitions for icons and text based on indicator proximity.
class FlipkartBottomNavBar extends StatefulWidget {
  final List<FlipkartNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? indicatorColor;
  final Color? backgroundColor;
  final double height;

  const FlipkartBottomNavBar({
    required this.items,
    required this.currentIndex,
    required this.onTap,
    super.key,
    this.activeColor,
    this.inactiveColor,
    this.indicatorColor,
    this.backgroundColor,
    this.height = 66.0,
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
      duration: const Duration(milliseconds: 320),
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
    // Position indicator centered at touch point
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
    final velocityBonus = (velocity / 1000.0).clamp(-0.8, 0.8);
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

    final activeColor = widget.activeColor ??
        (isDark ? const Color(0xFF4C93FF) : const Color(0xFF0D53FC));

    final inactiveColor = widget.inactiveColor ??
        (isDark ? const Color(0xFF8E95A2) : const Color(0xFF555B66));

    final indicatorColor = widget.indicatorColor ??
        (isDark ? const Color(0xFF2C323D) : const Color(0xFFE8ECEF));

    final borderColor = isDark
        ? const Color(0x14FFFFFF)
        : const Color(0x12000000);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final count = widget.items.length;
        final tabWidth = totalWidth / count;

        // The grey indicator capsule width & height
        final indicatorPaddingH = math.max(4.0, (tabWidth - 68.0) / 2);
        final indicatorWidth = tabWidth - (indicatorPaddingH * 2);
        final indicatorHeight = widget.height - 12.0;

        // Horizontal position of the sliding grey indicator
        final indicatorLeft =
            (_currentProgress * tabWidth) + indicatorPaddingH;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => _onHorizontalDragStart(d, totalWidth),
          onHorizontalDragUpdate: (d) => _onHorizontalDragUpdate(d, totalWidth),
          onHorizontalDragEnd: (d) => _onHorizontalDragEnd(d, totalWidth),
          onHorizontalDragCancel: _onHorizontalDragCancel,
          onTapUp: (d) => _onTapUp(d, totalWidth),
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(widget.height / 2),
              border: Border.all(color: borderColor, width: 1),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? const Color(0x59000000)
                      : const Color(0x140B192C),
                  blurRadius: 18,
                  offset: const Offset(0, 5),
                  spreadRadius: 0,
                ),
                BoxShadow(
                  color: isDark
                      ? const Color(0x33000000)
                      : const Color(0x080B192C),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // 1. Draggable & Animated Grey Indicator Capsule ("Grey wala circle")
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
                        borderRadius: BorderRadius.circular(indicatorHeight / 2),
                        boxShadow: _isDragging
                            ? [
                                BoxShadow(
                                  color: (isDark
                                          ? const Color(0x4D000000)
                                          : const Color(0x2E0D53FC)),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                    ),
                  ),
                ),

                // 2. Tab Items Layer
                Row(
                  children: List.generate(count, (index) {
                    final item = widget.items[index];

                    // Proximity of indicator to this tab [0.0 = far, 1.0 = exactly over]
                    final distance = (_currentProgress - index).abs();
                    final proximity = (1.0 - distance).clamp(0.0, 1.0);

                    // Interpolated color between inactive and active
                    final itemColor = Color.lerp(
                      inactiveColor,
                      activeColor,
                      proximity,
                    )!;

                    // Subtle scale bounce when indicator is centered
                    final scale = 1.0 + (0.07 * proximity);

                    final isSelected = index == widget.currentIndex;

                    return Expanded(
                      child: Center(
                        child: Transform.scale(
                          scale: scale,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                (proximity > 0.6 && item.activeIcon != null)
                                    ? item.activeIcon
                                    : item.icon,
                                size: 23,
                                color: itemColor,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: itemColor,
                                  letterSpacing: -0.1,
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
        );
      },
    );
  }
}
