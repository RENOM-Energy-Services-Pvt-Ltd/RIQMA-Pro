import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Main Splash Screen Widget
class WindFarmSplash extends StatefulWidget {
  final VoidCallback? onComplete;
  final Future<void>? initializationFuture;

  const WindFarmSplash({
    super.key, 
    this.onComplete,
    this.initializationFuture,
  });

  @override
  State<WindFarmSplash> createState() => _WindFarmSplashState();
}

class _WindFarmSplashState extends State<WindFarmSplash> with TickerProviderStateMixin {
  // Animation Controllers
  late AnimationController _dropController;
  late AnimationController _spinController;
  late AnimationController _birdFlyController;
  late AnimationController _linesFadeController;

  @override
  void initState() {
    super.initState();

    // 1. The Drop (0.0s - 1.8s)
    // Using a longer duration to accommodate the stagger and settling
    _dropController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // 2. The Spin (Infinite)
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(); // Linear speed, 4s per revolution

    // 3. The Flock (Starts 0.5s after Spin starts, which is after Drop ends)
    // We'll trigger this manually in the listener
    _birdFlyController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5), // Slow flight across screen
    );

    // 4. Transmission Lines (Fade In)
    _linesFadeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );



    // Choreography
    _dropController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Drop finished. 
        // Spin continues (no reset).

        // Phase 3: Birds overlap 0.5s after spin starts
        // Phase 3: Birds overlap 0.5s after spin starts
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _birdFlyController.forward();
        });

        // Phase 4: Transmission lines fade in
        _linesFadeController.forward();
      }
    });

    // Start the Sequence
    _dropController.forward();

    // Startup Logic: Wait for BOTH min duration AND initialization
    _handleStartup();
  }

  Future<void> _handleStartup() async {
    // Minimum Splash Duration: 4 Seconds
    // Minimum Splash Duration: 4 Seconds
    final minDurationFuture = Future<void>.delayed(const Duration(seconds: 4));
    
    // App Initialization (with 8s timeout to prevent hanging)
    final initFuture = widget.initializationFuture ?? Future.value();
    final safeInitFuture = initFuture.timeout(
      const Duration(seconds: 8), 
      onTimeout: () {
        debugPrint('WindFarmSplash: Initialization timed out, proceeding anyway.');
      },
    ).catchError((Object e) {
      debugPrint('WindFarmSplash: Initialization error: $e');
    });

    // Wait for both
    await Future.wait([minDurationFuture, safeInitFuture]);

    if (mounted && widget.onComplete != null) {
      widget.onComplete!();
    }
  }

  @override
  void dispose() {
    _dropController.dispose();
    _spinController.dispose();
    _birdFlyController.dispose();
    _linesFadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Media Query for responsive sizing
    final size = MediaQuery.of(context).size;
    
    // Base dimensions from the prompt's coordinate system (500 x 900)
    // We scale to fit width/height ensuring cover.
    // Actually, prompt says "Scaling logic... roughly 9:16... filling screen without distortion".
    // We'll implement this by using the logical 500x900 grid and scaling our drawings or usage of width/height.

    // Design dimensions (Logical coordinate space)
    const designWidth = 500.0;
    const designHeight = 900.0;

    // Calculate scale to cover the screen (BoxFit.cover equivalent)
    final scaleX = size.width / designWidth;
    final scaleY = size.height / designHeight;
    final scale = math.max(scaleX, scaleY);

    // Calculate centering offsets
    final scaledWidth = designWidth * scale;
    final scaledHeight = designHeight * scale;
    final offsetX = (size.width - scaledWidth) / 2;
    final offsetY = (size.height - scaledHeight) / 2;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // A. Sky (Background) - Fills entire screen independently
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, -0.4), // 50% 30%
                radius: 1.2,
                colors: [
                  Color(0xFF2E7D32), // 0%
                  Color(0xFF1B5E20), // 25%
                  Color(0xFF051005), // 60%
                  Color(0xFF000000), // 100%
                ],
                stops: [0.0, 0.25, 0.60, 1.0],
              ),
            ),
          ),

          // SCENE CONTAINER
          // This stack contains all elements positioned in the 500x900 design space
          // We transform it to scale and center it
          Positioned(
            left: offsetX,
            top: offsetY,
            width: scaledWidth,
            height: scaledHeight,
            child: ComponentStack(
              scale: scale, 
              dropController: _dropController,
              spinController: _spinController,
              linesFadeController: _linesFadeController,
              birdFlyController: _birdFlyController,
            ),
          ),
        ],
      ),
    );
  }

}

class ComponentStack extends StatelessWidget {
  final double scale;
  final AnimationController dropController;
  final AnimationController spinController;
  final AnimationController linesFadeController;
  final AnimationController birdFlyController;

  const ComponentStack({
    required this.scale, required this.dropController, required this.spinController, required this.linesFadeController, required this.birdFlyController, super.key,
  });

  @override
  Widget build(BuildContext context) {
    // We are now inside a 500x900 coordinate space (scaled)
    // All positions should use absolute 500x900 coordinates * scale? 
    // No, the parent Positioned has sized itself to `scaledWidth` x `scaledHeight`.
    // So 0,0 is top-left of the scaled area.
    // If we use specific pixel values from the design (e.g. "Left Turbine at x=75"), we must multiply by scale.
    // OR we can wrap this whole thing in a Transform.scale? 
    // Using FittedBox/Transform is easier logically:
    
    return FittedBox(
      fit: BoxFit.cover,
      alignment: Alignment.center,
      child: SizedBox(
        width: 500,
        height: 900,
        child: Stack(
          children: [
             // B. Background Hill
            RepaintBoundary(
              child: CustomPaint(
                painter: BackgroundHillPainter(),
                size: const Size(500, 900),
              ),
            ),

            // Transmission Lines (Fade In)
            RepaintBoundary(
              child: FadeTransition(
                opacity: linesFadeController,
                child: CustomPaint(
                  painter: TransmissionLinesPainter(),
                  size: const Size(500, 900),
                ),
              ),
            ),

            // C. Turbines
            // Left Turbine - Moved outwards (was 75)
            Positioned(
              left: 40, 
              bottom: 240, // Slightly higher to separate depth
              child: _AnimatedTurbineDrop(
                dropAnimation: CurvedAnimation(
                  parent: dropController,
                  curve: const Interval(0.1, 0.9, curve: Curves.elasticOut),
                ),
                spinController: spinController,
                height: 160, // Reduced from 190
              ),
            ),

            // Right Turbine - Moved outwards (was 75)
            Positioned(
              right: 40,
              bottom: 240, 
              child: _AnimatedTurbineDrop(
                dropAnimation: CurvedAnimation(
                  parent: dropController,
                  curve: const Interval(0.1, 0.9, curve: Curves.elasticOut),
                ),
                spinController: spinController,
                height: 160,
              ),
            ),

            // D. Foreground Hill
            RepaintBoundary(
              child: CustomPaint(
                painter: ForegroundHillPainter(),
                size: const Size(500, 900),
              ),
            ),

            // Center Turbine
            // x=250 (center), y=lower
            Positioned(
              left: 250 - (260 * 0.8 / 2), // Recalculated for height 260
              bottom: 110, // Lower
              child: _AnimatedTurbineDrop(
                dropAnimation: CurvedAnimation(
                  parent: dropController,
                  curve: const Interval(0.0, 0.8, curve: Curves.elasticOut),
                ),
                spinController: spinController,
                height: 260, // Reduced from 280
                scale: 1.1, // Reduced from 1.2
              ),
            ),

            // E. Birds
            AnimatedBuilder(
              animation: birdFlyController,
              builder: (context, child) {
                final t = birdFlyController.value;
                const startX = 550.0;
                const endX = -200.0;
                const startY = 150.0;
                const endY = 80.0;

                final currentX = startX + (endX - startX) * t;
                final currentY = startY + (endY - startY) * t;

                if (t == 0 || t == 1) return const SizedBox();

                return Positioned(
                  left: currentX,
                  top: currentY,
                  child: const BirdFlockWidget(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// WIDGETS
// ---------------------------------------------------------------------------

class _AnimatedTurbineDrop extends StatelessWidget {
  final Animation<double> dropAnimation;
  final AnimationController spinController;
  final double height;
  final double scale;

  const _AnimatedTurbineDrop({
    required this.dropAnimation,
    required this.spinController,
    required this.height,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    // Drop Physics: Fall from top (off-screen) to y=0 (relative to Positioned bottom)
    // We actually translate Y. 
    // Start: -ScreenHeight (approx)
    // End: 0
    return AnimatedBuilder(
      animation: dropAnimation,
      child: RepaintBoundary(
        child: TurbineWidget(
          height: height,
          spinController: spinController,
        ),
      ),
      builder: (context, child) {
        // Simple translation logic: 
        // value 0 -> -1000 offset
        // value 1 -> 0 offset
        final startOffset = -MediaQuery.of(context).size.height;
        final currentOffset = startOffset * (1 - dropAnimation.value);

        return Transform.translate(
          offset: Offset(0, currentOffset),
          child: Transform.scale(
            scale: scale,
            child: child,
          ),
        );
      },
    );
  }
}

class TurbineWidget extends StatelessWidget {
  final double height;
  final Listenable spinController;

  const TurbineWidget({
    required this.height, required this.spinController, super.key,
  });

  @override
  Widget build(BuildContext context) {
    // Aspect ratio roughly maintained: width is ~1/3 of height for the visual bounds including blades
    // But we need safe bounds for rotation.
    // Blade path is ~155 units long -> Diameter ~310.
    // We use a fixed container of 350 for the painter space, but we scale it based on tower height
    // to simulate perspective/size correctly.
    // Reference: Height 260 -> Scale 1.0 (Standard for Center Turbine)
    final rotorScale = height / 260.0;
    const viewBoxSize = 350.0; 
    final boxWidth = height * 0.8;

    return SizedBox(
      height: height,
      width: boxWidth, // Approximation
      child: Stack(
        clipBehavior: Clip.none, // Allow blades to rotate outside bounds
        alignment: Alignment.bottomCenter,
        children: [
          // Tower (Static)
          CustomPaint(
            painter: TurbineTowerPainter(),
            size: Size(height * 0.1, height), // Tower width ~10% of height
          ),
          
          // Hub & Blades (Spinning)
          // Positioned at top of tower. 
          // Center of rotation (viewBox center) should align with (boxWidth/2, 0)
          Positioned(
            top: -viewBoxSize / 2,
            left: (boxWidth / 2) - (viewBoxSize / 2),
            child: Transform.scale(
              scale: rotorScale,
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: spinController,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: (spinController as AnimationController).value * 2 * math.pi,
                      child: CustomPaint(
                        painter: TurbineBladesPainter(),
                        size: const Size(viewBoxSize, viewBoxSize),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BirdFlockWidget extends StatefulWidget {
  const BirdFlockWidget({super.key});

  @override
  State<BirdFlockWidget> createState() => _BirdFlockWidgetState();
}

class _BirdFlockWidgetState extends State<BirdFlockWidget> with SingleTickerProviderStateMixin {
  late AnimationController _flapController;

  @override
  void initState() {
    super.initState();
    // Rapid wing flap
    _flapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _flapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 60,
      child: Stack(
        children: [
          // Bird 1
          Positioned(top: 0, left: 0, child: _buildSingleBird()),
          // Bird 2 (Offset)
          Positioned(top: 20, left: 30, child: _buildSingleBird()),
          // Bird 3 (Offset)
          Positioned(top: 10, left: 60, child: _buildSingleBird()),
        ],
      ),
    );
  }

  Widget _buildSingleBird() {
    return AnimatedBuilder(
      animation: _flapController,
      builder: (context, child) {
        // Flap: ScaleY 1.0 to -0.6
        final scaleY = 1.0 - (_flapController.value * 1.6); // 1.0 -> -0.6 range approx
        return CustomPaint(
          painter: BirdPainter(wingScale: scaleY),
          size: const Size(30, 20),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// PAINTERS
// ---------------------------------------------------------------------------

class BackgroundHillPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF33691E)
      ..style = PaintingStyle.fill;

    final path = Path();
    // Wide curve peaking on right
    // Start low-ish on left, peak right
    path.moveTo(0, size.height * 0.75);
    path.quadraticBezierTo(
      size.width * 0.7, size.height * 0.6, // Control point high right
      size.width, size.height * 0.7, // End point
    );
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ForegroundHillPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF66BB6A), Color(0xFF1B5E20), Color(0xFF051005)],
        stops: [0.0, 0.9, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    // Complex wave rising in middle
    path.moveTo(0, size.height);
    path.lineTo(0, size.height * 0.85);
    
    // Wave 1
    path.quadraticBezierTo(
      size.width * 0.25, size.height * 0.9, 
      size.width * 0.5, size.height * 0.75, // Peak
    );
    
    // Wave 2
    path.quadraticBezierTo(
      size.width * 0.75, size.height * 0.65, 
      size.width, size.height * 0.9,
    );
    
    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class TurbineTowerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFBDBDBD), Color(0xFFFFFFFF), Color(0xFFBDBDBD)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    // Tapered rectangle
    final path = Path();
    final w = size.width;
    final h = size.height;
    
    path.moveTo(w * 0.3, 0); // Top left (narrow)
    path.lineTo(w * 0.7, 0); // Top right
    path.lineTo(w, h);       // Bottom right (wide)
    path.lineTo(0, h);       // Bottom left
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class TurbineBladesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    // Draw 3 Blades
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(i * 120 * (math.pi / 180));
      
      _drawBlade(canvas, i);
      
      canvas.restore();
    }

    // Draw Hub Cap
    _drawHub(canvas, center);
  }

  void _drawBlade(Canvas canvas, int index) {
    // Blade Path: M -5 -17 Q -24 -90 0 -155 Q 24 -90 5 -17 Z
    // Tip properties: Blade 1 (Red), 2 (Blue), 3 (Yellow)
    const bladeColor = Color(0xFFFFFFFF);
    final tipColor = [
      const Color(0xFFEA4335), // Red
      const Color(0xFF4285F4), // Blue
      const Color(0xFFFBBC05), // Yellow
    ][index % 3];

    final paint = Paint()
      ..color = bladeColor
      ..style = PaintingStyle.fill;

    // Convert SVG path commands to Dart Path
    final path = Path();
    path.moveTo(-5, -17);
    path.quadraticBezierTo(-24, -90, 0, -155);
    path.quadraticBezierTo(24, -90, 5, -17);
    path.close();

    // Draw White Blade
    canvas.drawPath(path, paint);

    // Draw Tip with Clipping
    // Clip Rect: x="-25" y="-160" width="50" height="35"
    canvas.save();
    canvas.clipPath(path); // Clip to blade shape
    
    final tipPaint = Paint()..color = tipColor;
    // The rect covers the top part of the blade
    canvas.drawRect(
      const Rect.fromLTWH(-25, -160, 50, 35),
      tipPaint,
    );
    canvas.restore();
  }

  void _drawHub(Canvas canvas, Offset center) {
    // Small grey circle behind
    final greyPaint = Paint()..color = const Color(0xFFB0BEC5);
    canvas.drawCircle(center, 12, greyPaint);

    // Main Cap: Radial Gradient
    final gradient = const RadialGradient(
      colors: [Color(0xFFFFFFFF), Color(0xFFF5F5F5), Color(0xFFCFD8DC)],
    ).createShader(Rect.fromCircle(center: center, radius: 10));

    final capPaint = Paint()..shader = gradient;
    canvas.drawCircle(center, 9, capPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class BirdPainter extends CustomPainter {
  final double wingScale;

  BirdPainter({required this.wingScale});

  @override
  void paint(Canvas canvas, Size size) {
    final bodyPaint = Paint()..color = const Color(0xFF29B6F6); // Light Blue
    final beakPaint = Paint()..color = const Color(0xFFFFEB3B); // Yellow
    final wingPaint = Paint()..color = const Color(0xFFFF7043); // Orange

    canvas.save();
    // Scale to fit size
    // Original path coords roughly 0,0 to 30,10.
    final scale = size.width / 30;
    canvas.scale(scale);

    // Beak (Simple triangle or implied? Path not provided for beak, assuming part of body or simple add)
    // "Bird Body: M0,0 Q15,-5 30,0 Q15,8 0,0 Z"
    // Does not look like it includes beak.
    // I'll draw a small beak triangle at the head (30,0).
    final beakPath = Path();
    beakPath.moveTo(28, -2);
    beakPath.lineTo(35, 0);
    beakPath.lineTo(28, 2);
    beakPath.close();
    canvas.drawPath(beakPath, beakPaint);

    // Body
    final bodyPath = Path();
    bodyPath.moveTo(0, 0);
    bodyPath.quadraticBezierTo(15, -5, 30, 0);
    bodyPath.quadraticBezierTo(15, 8, 0, 0);
    bodyPath.close();
    canvas.drawPath(bodyPath, bodyPaint);

    // Wing
    // Wing Path: M8,-2 Q18,-18 28,-2 Q18,-6 8,-2 Z
    // We apply scale transform to wing for flapping
    // Pivot around (18, -2) approx center base of wing
    canvas.save();
    canvas.translate(18, -2);
    canvas.scale(1.0, wingScale);
    canvas.translate(-18, 2);

    final wingPath = Path();
    wingPath.moveTo(8, -2);
    wingPath.quadraticBezierTo(18, -18, 28, -2);
    wingPath.quadraticBezierTo(18, -6, 8, -2);
    wingPath.close();
    canvas.drawPath(wingPath, wingPaint);
    
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BirdPainter oldDelegate) => oldDelegate.wingScale != wingScale;
}

class TransmissionLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path = Path();
    
    // Coordinates must match the Positioned widgets in the Stack
    // Design Size: 500 x 900
    // Left Turbine: left 40, width 128 (160*0.8), bottom 240
    // Center X = 40 + 64 = 104. Base Y = 900 - 240 = 660.
    const leftX = 104.0;
    const leftY = 660.0;

    // Center Turbine: center 250, bottom 110
    // Center X = 250. Base Y = 900 - 110 = 790.
    const centerX = 250.0;
    const centerY = 790.0;

    // Right Turbine: right 40, width 128, bottom 240
    // Center X = 500 - 40 - 64 = 396. Base Y = 660.
    const rightX = 396.0;
    const rightY = 660.0;

    // Draw Switch Yards (Transformers) FIRST so lines go "into" them or behind?
    // Let's draw lines first, then switch yards on top.
    
    // Line Left -> Center
    path.moveTo(leftX, leftY);
    path.quadraticBezierTo(
      (leftX + centerX) / 2, leftY + 60, // Deeper dip
      centerX, centerY,
    );

    // Line Center -> Right
    path.moveTo(centerX, centerY);
    path.quadraticBezierTo(
      (centerX + rightX) / 2, rightY + 60, // Deeper dip
      rightX, rightY,
    );
    
    // Offscreen connections
    path.moveTo(leftX, leftY);
    path.lineTo(0, leftY + 20);

    path.moveTo(rightX, rightY);
    path.lineTo(size.width, rightY + 20);

    canvas.drawPath(path, paint);

    // Draw Switch Yards
    _drawSwitchYard(canvas, const Offset(leftX, leftY));
    _drawSwitchYard(canvas, const Offset(centerX, centerY), scale: 1.2);
    _drawSwitchYard(canvas, const Offset(rightX, rightY));
  }

  void _drawSwitchYard(Canvas canvas, Offset pos, {double scale = 1.0}) {
    final paint = Paint()
      ..color = const Color(0xFF455A64) // Blue-grey dark
      ..style = PaintingStyle.fill;
    
    final detailPaint = Paint()
      ..color = const Color(0xFF90A4AE) // Lighter grey
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    const w = 30.0;
    const h = 20.0;

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.scale(scale);
    canvas.translate(-w/2, -h); // Draw sitting ON the line/ground

    // Box
    const rect = Rect.fromLTWH(0, 0, w, h);
    canvas.drawRect(rect, paint);
    canvas.drawRect(rect, detailPaint);

    // Details (Grid)
    canvas.drawLine(const Offset(5, 5), const Offset(25, 5), detailPaint);
    canvas.drawLine(const Offset(5, 10), const Offset(25, 10), detailPaint);
    canvas.drawLine(const Offset(5, 15), const Offset(25, 15), detailPaint);

    // Insulator / Connector (Small stick up)
    canvas.drawLine(const Offset(w/2, 0), const Offset(w/2, -10), detailPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
