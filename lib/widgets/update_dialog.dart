import 'package:flutter/material.dart';
import '../services/app_update_service.dart';

class UpdateDialog extends StatefulWidget {
  final AppUpdateInfo updateInfo;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
  });

  /// Static helper to display the dialog
  static Future<void> show(BuildContext context, AppUpdateInfo info) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (context) => UpdateDialog(updateInfo: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _downloadStatus = '';
  String? _errorMessage;

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _downloadStatus = 'Starting download...';
    });

    try {
      await AppUpdateService.instance.downloadAndInstall(
        apkUrl: widget.updateInfo.apkUrl,
        onProgress: (progress, received, total) {
          if (!mounted) return;
          final receivedMb = (received / (1024 * 1024)).toStringAsFixed(1);
          final totalMb = (total / (1024 * 1024)).toStringAsFixed(1);
          setState(() {
            _progress = progress;
            _downloadStatus = '$receivedMb MB / $totalMb MB (${(progress * 100).toInt()}%)';
          });
        },
      );

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadStatus = 'Launching installer...';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !widget.updateInfo.forceUpdate && !_isDownloading,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 10,
        backgroundColor: Theme.of(context).cardColor,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Icon
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00897B).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: Color(0xFF00897B),
                    size: 40,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                'New Update Available',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),

              // Version Badges
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Current: v${widget.updateInfo.currentVersion}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey[300] : Colors.grey[700],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00897B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF00897B).withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'New: v${widget.updateInfo.latestVersion}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00897B),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Release Notes Box
              if (widget.updateInfo.releaseNotes.isNotEmpty) ...[
                Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "What's New:",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.updateInfo.releaseNotes,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.grey[300] : Colors.grey[800],
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Downloading UI or Error
              if (_isDownloading) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        minHeight: 8,
                        backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00897B)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _downloadStatus,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ] else if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Action Buttons
              if (!_isDownloading) ...[
                ElevatedButton(
                  onPressed: _startDownload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                    _errorMessage != null ? 'Retry Download' : 'Update Now',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (!widget.updateInfo.forceUpdate) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Later',
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
