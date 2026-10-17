import 'dart:math' as math;
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
  double _targetProgress = 0.0;
  bool _isDragging = false;
  int _lastHapticIndex = -1;

  // Drag tracking anchor points to prevent sudden jumps
  double _dragStartX = 0.0;
  double _dragStartProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _currentProgress = widget.currentIndex.toDouble();
    _targetProgress = widget.currentIndex.toDouble();
    _lastHapticIndex = widget.currentIndex;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _animation = Tween<double>(
      begin: _currentProgress,
      end: _currentProgress,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Cubic(0.22, 1.0, 0.36, 1.0),
      ),
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
    if (oldWidget.currentIndex != widget.currentIndex) {
      // Avoid interrupting an in-progress drag or an animation already moving to this target
      if (!_isDragging &&
          (!_animController.isAnimating ||
              (_targetProgress - widget.currentIndex.toDouble()).abs() > 0.01)) {
        _animateTo(widget.currentIndex.toDouble());
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _animateTo(double targetValue) {
    if ((_currentProgress - targetValue).abs() < 0.001) {
      _currentProgress = targetValue;
      return;
    }

    _targetProgress = targetValue;
    _animController.stop();

    // Preserve exact visual position as the animation origin
    final start = _currentProgress;

    _animation = Tween<double>(
      begin: start,
      end: targetValue,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Cubic(0.22, 1.0, 0.36, 1.0),
      ),
    );

    // Forward from 0.0 without reset() so listeners start strictly from 'start'
    _animController.forward(from: 0.0);
  }

  void _onHorizontalDragStart(DragStartDetails details, double totalWidth) {
    _animController.stop();
    _dragStartX = details.localPosition.dx;
    _dragStartProgress = _currentProgress;
    setState(() {
      _isDragging = true;
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details, double totalWidth) {
    final tabWidth = totalWidth / widget.items.length;
    final deltaProgress = (details.localPosition.dx - _dragStartX) / tabWidth;
    final newProgress = (_dragStartProgress + deltaProgress)
        .clamp(0.0, (widget.items.length - 1).toDouble());

    final nearestIndex = newProgress.round();
    if (nearestIndex != _lastHapticIndex) {
      _lastHapticIndex = nearestIndex;
      HapticFeedback.selectionClick();
    }

    setState(() {
      _currentProgress = newProgress;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details, double totalWidth) {
    setState(() {
      _isDragging = false;
    });

    final velocity = details.primaryVelocity ?? 0.0;
    // Fling bonus based on swipe speed
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

    // Renom Teal default active color
    final activeColor = widget.activeColor ?? const Color(0xFF00897B);

    final inactiveColor = widget.inactiveColor ??
        (isDark ? const Color(0xFF9EA3AE) : const Color(0xFF6B7280));

    final glassColors = widget.backgroundColor != null
        ? [
            widget.backgroundColor!.withValues(alpha: isDark ? 0.72 : 0.72),
            widget.backgroundColor!.withValues(alpha: isDark ? 0.82 : 0.48),
          ]
        : (isDark
            ? [
                const Color(0xFF22262F).withValues(alpha: 0.72),
                const Color(0xFF14171E).withValues(alpha: 0.82),
              ]
            : [
                Colors.white.withValues(alpha: 0.72),
                Colors.white.withValues(alpha: 0.48),
              ]);

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
            final baseIndicatorWidth = tabWidth - (indicatorPaddingH * 2);
            final indicatorHeight = widget.height - 10.0;

            // Fluid sinusoidal elastic stretch between tabs
            final fractionalDistance = (_currentProgress % 1.0);
            final stretchFactor = math.sin(fractionalDistance * math.pi).abs();
            final dynamicStretch = stretchFactor * 14.0;
            final indicatorWidth = baseIndicatorWidth + dynamicStretch;

            // Horizontal position of the sliding indicator centered with dynamic stretch
            final indicatorLeft =
                (_currentProgress * tabWidth) + indicatorPaddingH - (dynamicStretch / 2);

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
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    height: widget.height,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(widget.height / 2),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: glassColors,
                      ),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.20)
                            : Colors.white.withValues(alpha: 0.85),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? const Color(0x66000000)
                              : const Color(0x18000000),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                          spreadRadius: 0,
                        ),
                        BoxShadow(
                          color: isDark
                              ? const Color(0x33000000)
                              : const Color(0x0A000000),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        // Subtle top rim specular highlight
                        Positioned(
                          top: 1,
                          left: 20,
                          right: 20,
                          height: 1.0,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.0),
                                  Colors.white.withValues(alpha: isDark ? 0.30 : 0.70),
                                  Colors.white.withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Ambient Neon Underglow Light
                        Positioned(
                          left: indicatorLeft + (indicatorWidth * 0.1),
                          top: (widget.height - indicatorHeight) / 2 + 2,
                          width: indicatorWidth * 0.8,
                          height: indicatorHeight - 4,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: activeColor.withValues(
                                      alpha: isDark ? 0.48 : 0.30,
                                    ),
                                    blurRadius: _isDragging ? 22 : 16,
                                    spreadRadius: _isDragging ? 3 : 1.5,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Sliding Smart Pure Glass Capsule
                        Positioned(
                          left: indicatorLeft,
                          top: (widget.height - indicatorHeight) / 2,
                          width: indicatorWidth,
                          height: indicatorHeight,
                          child: AnimatedScale(
                            scale: _isDragging ? 1.05 : 1.0,
                            duration: const Duration(milliseconds: 140),
                            curve: Curves.easeOut,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: isDark
                                      ? [
                                          Colors.white.withValues(alpha: 0.32),
                                          Colors.white.withValues(alpha: 0.10),
                                          activeColor.withValues(alpha: 0.32),
                                        ]
                                      : [
                                          Colors.white.withValues(alpha: 0.98),
                                          Colors.white.withValues(alpha: 0.60),
                                          activeColor.withValues(alpha: 0.22),
                                        ],
                                  stops: const [0.0, 0.42, 1.0],
                                ),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.35)
                                      : Colors.white.withValues(alpha: 0.95),
                                  width: 1.3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: (isDark ? Colors.black : activeColor).withValues(
                                      alpha: isDark
                                          ? (_isDragging ? 0.60 : 0.35)
                                          : (_isDragging ? 0.26 : 0.14),
                                    ),
                                    blurRadius: _isDragging ? 16 : 8,
                                    offset: const Offset(0, 3),
                                  ),
                                  if (!isDark)
                                    BoxShadow(
                                      color: Colors.white.withValues(alpha: 0.85),
                                      blurRadius: 4,
                                      offset: const Offset(0, -1),
                                      spreadRadius: 0.5,
                                    ),
                                ],
                              ),
                              child: Stack(
                                children: [
                                  // Specular glass glare highlight strip at top of capsule
                                  Positioned(
                                    top: 2,
                                    left: 10,
                                    right: 10,
                                    height: 1.5,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(2),
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.white.withValues(alpha: 0.0),
                                            Colors.white.withValues(alpha: isDark ? 0.40 : 0.90),
                                            Colors.white.withValues(alpha: 0.0),
                                          ],
                                        ),
                                      ),
                                    ),
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

                            final curvedProximity = Curves.easeOutBack.transform(proximity);
                            // 3D vertical lift & spring scale
                            final iconOffsetY = -2.2 * proximity;
                            final iconScale = 1.0 + (0.14 * curvedProximity);
                            final isSelected = proximity > 0.5;

                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Transform.translate(
                                      offset: Offset(0, iconOffsetY),
                                      child: Transform.scale(
                                        scale: iconScale,
                                        child: Icon(
                                          (proximity > 0.6 && item.activeIcon != null)
                                              ? item.activeIcon
                                              : item.icon,
                                          size: 22,
                                          color: itemColor,
                                          shadows: isSelected
                                              ? [
                                                  Shadow(
                                                    color: activeColor.withValues(
                                                      alpha: isDark ? 0.65 : 0.40,
                                                    ),
                                                    blurRadius: 10,
                                                  ),
                                                ]
                                              : null,
                                        ),
                                      ),
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
                                            letterSpacing: isSelected ? -0.1 : -0.2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
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
