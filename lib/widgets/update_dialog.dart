import 'package:flutter/material.dart';
import '../services/app_update_service.dart';

class UpdateDialog extends StatefulWidget {
  final AppUpdateInfo updateInfo;

  const UpdateDialog({
    required this.updateInfo,
    super.key,
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

class _UpdateDialogState extends State<UpdateDialog> with WidgetsBindingObserver {
  bool _isDownloading = false;
  bool _isInstalling = false;
  bool _needsPermission = false;
  bool _hasDownloadedApk = false;
  double _progress = 0.0;
  String _downloadStatus = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInitialState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkInitialState() async {
    try {
      // 1. Clean stale/old APKs right away so any obsolete riqma_update.apk is wiped
      await AppUpdateService.instance.cleanOldApks(
        keepVersion: widget.updateInfo.latestVersion,
      );

      final downloaded = await AppUpdateService.instance.hasDownloadedApk(
        targetVersion: widget.updateInfo.latestVersion,
      );
      final canInstall = await AppUpdateService.instance.canRequestPackageInstalls();
      if (mounted) {
        setState(() {
          _hasDownloadedApk = downloaded;
          if (!canInstall && downloaded) {
            _needsPermission = true;
          }
        });
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissionOnResume();
    }
  }

  Future<void> _checkPermissionOnResume() async {
    final canInstall = await AppUpdateService.instance.canRequestPackageInstalls();
    if (mounted) {
      setState(() {
        if (canInstall) {
          _needsPermission = false;
        }
      });
    }

    // If permission was granted and APK is downloaded, automatically launch installer!
    if (canInstall) {
      final downloaded = await AppUpdateService.instance.hasDownloadedApk(
        targetVersion: widget.updateInfo.latestVersion,
      );
      if (downloaded && !_isDownloading && !_isInstalling) {
        await _installDownloadedApk();
      }
    }
  }

  Future<void> _openSettings() async {
    await AppUpdateService.instance.openInstallPermissionSettings();
  }

  Future<void> _installDownloadedApk() async {
    setState(() {
      _isInstalling = true;
      _errorMessage = null;
    });

    try {
      final canInstall = await AppUpdateService.instance.canRequestPackageInstalls();
      if (!canInstall) {
        setState(() {
          _isInstalling = false;
          _needsPermission = true;
        });
        await _openSettings();
        return;
      }

      await AppUpdateService.instance.installDownloadedApk(widget.updateInfo.latestVersion);
      if (mounted) {
        setState(() {
          _isInstalling = false;
        });
      }
    } on PermissionDeniedException {
      if (mounted) {
        setState(() {
          _isInstalling = false;
          _needsPermission = true;
        });
        await _openSettings();
      }
    } catch (e) {
      if (mounted) {
        final err = e.toString().replaceAll('Exception: ', '');
        if (err.contains('REQUEST_INSTALL_PACKAGES') || err.contains('Permission denied')) {
          setState(() {
            _isInstalling = false;
            _needsPermission = true;
          });
          await _openSettings();
        } else {
          setState(() {
            _isInstalling = false;
            _errorMessage = err;
          });
        }
      }
    }
  }

  Future<void> _handleAction() async {
    // If APK is already downloaded, try to install directly
    if (_hasDownloadedApk) {
      await _installDownloadedApk();
      return;
    }

    // Pre-check permission before downloading so user can enable it first if needed
    final canInstall = await AppUpdateService.instance.canRequestPackageInstalls();
    if (!canInstall) {
      setState(() {
        _needsPermission = true;
      });
      await _openSettings();
      return;
    }

    await _startDownload();
  }

  Future<void> _startDownload({bool force = false}) async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _downloadStatus = 'Starting download...';
    });

    try {
      if (force) {
        await AppUpdateService.instance.cleanOldApks();
      }

      await AppUpdateService.instance.downloadAndInstall(
        apkUrl: widget.updateInfo.apkUrl,
        targetVersion: widget.updateInfo.latestVersion,
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
          _hasDownloadedApk = true;
          _downloadStatus = 'Launching installer...';
        });
      }
    } on PermissionDeniedException {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _hasDownloadedApk = true;
          _needsPermission = true;
        });
        await _openSettings();
      }
    } catch (e) {
      if (mounted) {
        final err = e.toString().replaceAll('Exception: ', '');
        if (err.contains('REQUEST_INSTALL_PACKAGES') || err.contains('Permission denied')) {
          setState(() {
            _isDownloading = false;
            _hasDownloadedApk = true;
            _needsPermission = true;
          });
          await _openSettings();
        } else {
          setState(() {
            _isDownloading = false;
            _errorMessage = err;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !widget.updateInfo.forceUpdate && !_isDownloading && !_isInstalling,
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

              // Permission Guidance Box
              if (_needsPermission) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF332A00) : const Color(0xFFFFF9E6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? const Color(0xFF665500) : const Color(0xFFFFE082),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.security_update_good_rounded,
                            color: isDark ? const Color(0xFFFFD54F) : const Color(0xFFE65100),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Install Permission Required',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isDark ? const Color(0xFFFFD54F) : const Color(0xFFE65100),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '1. Tap "Open Settings" below.\n'
                        '2. Turn ON "Allow from this source".\n'
                        '3. Return here to complete installation.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[300] : const Color(0xFF5D4037),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _openSettings,
                          icon: const Icon(Icons.settings, size: 16),
                          label: const Text('Open Settings'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark ? const Color(0xFFFFD54F) : const Color(0xFFE65100),
                            side: BorderSide(
                              color: isDark ? const Color(0xFFFFD54F) : const Color(0xFFE65100),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    ],
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
                  onPressed: _isInstalling ? null : _handleAction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00897B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isInstalling
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          _needsPermission
                              ? (_hasDownloadedApk ? "I've Enabled It - Install Now" : 'Enable & Update')
                              : (_hasDownloadedApk
                                  ? 'Install Now'
                                  : (_errorMessage != null ? 'Retry Download' : 'Update Now')),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
                if (_hasDownloadedApk && !_isInstalling) ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () => _startDownload(force: true),
                    icon: const Icon(Icons.refresh, size: 16, color: Color(0xFF00897B)),
                    label: const Text(
                      'Re-download (Fresh File)',
                      style: TextStyle(fontSize: 13, color: Color(0xFF00897B), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
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
