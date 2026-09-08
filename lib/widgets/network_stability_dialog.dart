import 'dart:async';
import 'package:flutter/material.dart';
import '../services/network_stability_service.dart';

/// Pre-submission modal dialog that verifies network stability, latency,
/// and upload capability before initiating heavy audit submission.
class NetworkStabilityDialog extends StatefulWidget {
  final VoidCallback onStabilityConfirmed;

  const NetworkStabilityDialog({
    required this.onStabilityConfirmed,
    super.key,
  });

  /// Static helper to display the dialog easily from any screen
  static Future<void> show({
    required BuildContext context,
    required VoidCallback onStabilityConfirmed,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => NetworkStabilityDialog(
        onStabilityConfirmed: onStabilityConfirmed,
      ),
    );
  }

  @override
  State<NetworkStabilityDialog> createState() => _NetworkStabilityDialogState();
}

class _NetworkStabilityDialogState extends State<NetworkStabilityDialog>
    with SingleTickerProviderStateMixin {
  bool _isChecking = true;
  bool _isSuccess = false;
  String _stepMessage = 'Initializing network probe...';
  double _progress = 0.1;
  NetworkStabilityResult? _result;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _runStabilityCheck();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _runStabilityCheck() async {
    setState(() {
      _isChecking = true;
      _isSuccess = false;
      _stepMessage = 'Pinging network gateway...';
      _progress = 0.15;
      _result = null;
    });

    final result = await NetworkStabilityService.instance.checkStability(
      onProgress: (step, prog) {
        if (mounted) {
          setState(() {
            _stepMessage = step;
            _progress = prog;
          });
        }
      },
    );

    if (!mounted) return;

    if (result.isStable) {
      setState(() {
        _isChecking = false;
        _isSuccess = true;
        _result = result;
        _stepMessage = 'Network Verified (Ping: ${result.latencyMs}ms)';
      });

      // Brief delay to allow the user to see green confirmation before auto-submitting
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        Navigator.of(context).pop(); // Close dialog
        widget.onStabilityConfirmed(); // Trigger actual submit
      }
    } else {
      setState(() {
        _isChecking = false;
        _isSuccess = false;
        _result = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 12,
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Icon Header with Pulse Animation ──
            if (_isChecking)
              ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00897B).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.sensors_rounded,
                      size: 40,
                      color: Color(0xFF00897B),
                    ),
                  ),
                ),
              )
            else if (_isSuccess)
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 44,
                  color: Colors.green.shade700,
                ),
              )
            else
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.signal_cellular_connected_no_internet_0_bar_rounded,
                  size: 42,
                  color: Colors.red.shade700,
                ),
              ),

            const SizedBox(height: 20),

            // ── Title ──
            Text(
              _isChecking
                  ? 'Checking Network Stability'
                  : _isSuccess
                      ? 'Network Stable'
                      : 'Network Too Weak',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'Outfit',
                color: _isChecking
                    ? const Color(0xFF1A1F36)
                    : _isSuccess
                        ? Colors.green.shade800
                        : Colors.red.shade800,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 12),

            // ── Description / Message ──
            if (_isChecking) ...[
              Text(
                _stepMessage,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  fontFamily: 'Outfit',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00897B)),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Verifying speed & packet stability for safe photo upload...',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  fontFamily: 'Outfit',
                ),
                textAlign: TextAlign.center,
              ),
            ] else if (_isSuccess) ...[
              Text(
                'Connection meets safety standards. Proceeding to submit audit...',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  fontFamily: 'Outfit',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Text(
                  '${_result?.diagnosticDetails ?? "Ping: ${_result?.latencyMs ?? 0}ms"} ✓',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade800,
                  ),
                ),
              ),
            ] else ...[
              // Exact requested prompt
              const Text(
                'Sorry, your network is too weak. Please retry from another place where network is available.',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                  fontFamily: 'Outfit',
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              if (_result != null && _result!.diagnosticDetails != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200, width: 0.8),
                  ),
                  child: Text(
                    _result!.diagnosticDetails!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 24),

              // ── Action Buttons ──
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        side: BorderSide(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                          fontFamily: 'Outfit',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00897B), Color(0xFF1565C0)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00897B).withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _runStabilityCheck,
                        icon: const Icon(Icons.refresh_rounded, size: 20, color: Colors.white),
                        label: const Text(
                          'Retry Test',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
