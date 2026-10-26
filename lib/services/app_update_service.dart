import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class PermissionDeniedException implements Exception {
  final String message;
  const PermissionDeniedException(this.message);

  @override
  String toString() => message;
}

class AppUpdateInfo {
  final String latestVersion;
  final int latestBuildNumber;
  final String currentVersion;
  final int currentBuildNumber;
  final String apkUrl;
  final String releaseNotes;
  final bool forceUpdate;
  final bool hasUpdate;

  AppUpdateInfo({
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.currentVersion,
    required this.currentBuildNumber,
    required this.apkUrl,
    required this.releaseNotes,
    required this.forceUpdate,
    required this.hasUpdate,
  });
}

class AppUpdateService {
  static final AppUpdateService instance = AppUpdateService._internal();
  AppUpdateService._internal();

  static const MethodChannel _installerChannel =
      MethodChannel('com.example.riqma_pro/app_installer');

  static const String _githubLatestReleaseApi =
      'https://api.github.com/repos/RENOM-Energy-Services-Pvt-Ltd/RIQMA-Pro/releases/latest';

  /// Check whether the app has permission to install unknown apps
  Future<bool> canRequestPackageInstalls() async {
    if (!Platform.isAndroid) return true;
    try {
      final bool? canInstall =
          await _installerChannel.invokeMethod<bool>('canRequestPackageInstalls');
      return canInstall ?? true;
    } catch (e) {
      debugPrint('AppUpdateService: Error checking install permission: $e');
      return true;
    }
  }

  /// Open Android System Settings for "Allow from this source"
  Future<bool> openInstallPermissionSettings() async {
    if (!Platform.isAndroid) return true;
    try {
      final bool? opened =
          await _installerChannel.invokeMethod<bool>('openInstallPermissionSettings');
      return opened ?? false;
    } catch (e) {
      debugPrint('AppUpdateService: Error opening install settings: $e');
      return false;
    }
  }

  /// Get the cached downloaded APK file
  Future<File> getDownloadedApkFile() async {
    final tempDir = await getTemporaryDirectory();
    return File('${tempDir.path}/riqma_update.apk');
  }

  /// Check if the APK has already been downloaded to cache
  Future<bool> hasDownloadedApk() async {
    final file = await getDownloadedApkFile();
    return await file.exists();
  }

  /// Installs an already-downloaded APK after verifying permissions
  Future<void> installDownloadedApk() async {
    final file = await getDownloadedApkFile();
    if (!await file.exists()) {
      throw Exception('Downloaded update file not found.');
    }

    // 1. Verify Permission
    final hasPermission = await canRequestPackageInstalls();
    if (!hasPermission) {
      throw const PermissionDeniedException(
        'Permission denied: android.permission.REQUEST_INSTALL_PACKAGES',
      );
    }

    // 2. Launch Installer
    final result = await OpenFile.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );

    if (result.type != ResultType.done) {
      throw Exception('Failed to open installer: ${result.message}');
    }
  }

  /// Check whether an update is available (from Firestore with GitHub fallback)
  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g. "1.0.1"
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

      // 1. Try Firestore app_config/version first
      try {
        final doc = await FirebaseFirestore.instance
            .collection('app_config')
            .doc('version')
            .get();

        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          final latestVersion = (data['latest_version'] ?? currentVersion).toString().trim();
          final latestBuildNumber = int.tryParse(data['build_number']?.toString() ?? '0') ?? 0;
          final apkUrl = (data['apk_url'] ?? '').toString().trim();
          final releaseNotes = (data['release_notes'] ?? 'Bug fixes and performance improvements.').toString();
          final forceUpdate = data['force_update'] == true;

          final hasUpdate = _isNewer(
            currentVersion: currentVersion,
            currentBuild: currentBuildNumber,
            latestVersion: latestVersion,
            latestBuild: latestBuildNumber,
          );

          if (hasUpdate && apkUrl.isNotEmpty) {
            return AppUpdateInfo(
              latestVersion: latestVersion,
              latestBuildNumber: latestBuildNumber,
              currentVersion: currentVersion,
              currentBuildNumber: currentBuildNumber,
              apkUrl: apkUrl,
              releaseNotes: releaseNotes,
              forceUpdate: forceUpdate,
              hasUpdate: true,
            );
          }
        }
      } catch (e) {
        debugPrint('AppUpdateService: Firestore version check skipped: $e');
      }

      // 2. Fallback: GitHub Releases API
      try {
        final response = await http
            .get(
              Uri.parse(_githubLatestReleaseApi),
              headers: {
                'Accept': 'application/vnd.github.v3+json',
                'User-Agent': 'RIQMA-Pro-App',
                'Cache-Control': 'no-cache',
              },
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final Map<String, dynamic> data =
              Map<String, dynamic>.from(jsonDecode(response.body) as Map);

          // e.g. "v1.0.2" -> "1.0.2"
          String rawTag = (data['tag_name'] ?? '').toString().replaceAll('v', '').trim();
          final releaseNotes = (data['body'] ?? 'New release available with performance improvements.').toString();

          // Locate APK asset in release
          String apkUrl = '';
          final assets = data['assets'] as List<dynamic>? ?? [];
          for (final asset in assets) {
            final name = (asset['name'] ?? '').toString().toLowerCase();
            if (name.endsWith('.apk')) {
              apkUrl = (asset['browser_download_url'] ?? '').toString();
              break;
            }
          }

          if (rawTag.isNotEmpty && apkUrl.isNotEmpty) {
            final hasUpdate = _isNewer(
              currentVersion: currentVersion,
              currentBuild: currentBuildNumber,
              latestVersion: rawTag,
              latestBuild: 0,
            );

            if (hasUpdate) {
              return AppUpdateInfo(
                latestVersion: rawTag,
                latestBuildNumber: 0,
                currentVersion: currentVersion,
                currentBuildNumber: currentBuildNumber,
                apkUrl: apkUrl,
                releaseNotes: releaseNotes,
                forceUpdate: false,
                hasUpdate: true,
              );
            }
          }
        }
      } catch (e) {
        debugPrint('AppUpdateService: GitHub Releases API check skipped: $e');
      }

      // No update found or current is latest
      return AppUpdateInfo(
        latestVersion: currentVersion,
        latestBuildNumber: currentBuildNumber,
        currentVersion: currentVersion,
        currentBuildNumber: currentBuildNumber,
        apkUrl: '',
        releaseNotes: '',
        forceUpdate: false,
        hasUpdate: false,
      );
    } catch (e) {
      debugPrint('AppUpdateService: Error checking for update: $e');
      return null;
    }
  }

  /// Downloads APK directly and launches Android Package Installer
  Future<void> downloadAndInstall({
    required String apkUrl,
    required void Function(double progress, int receivedBytes, int totalBytes) onProgress,
  }) async {
    final client = http.Client();
    final tempDir = await getTemporaryDirectory();
    final apkFile = File('${tempDir.path}/riqma_update.apk');

    try {
      final request = http.Request('GET', Uri.parse(apkUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Download failed with status: ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      var receivedBytes = 0;

      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final sink = apkFile.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          final progress = receivedBytes / totalBytes;
          onProgress(progress, receivedBytes, totalBytes);
        }
      }

      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }

    // Pre-Install Permission Check
    final hasPermission = await canRequestPackageInstalls();
    if (!hasPermission) {
      throw const PermissionDeniedException(
        'Permission denied: android.permission.REQUEST_INSTALL_PACKAGES',
      );
    }

    // Launch the Android System Package Installer
    final result = await OpenFile.open(
      apkFile.path,
      type: 'application/vnd.android.package-archive',
    );

    if (result.type != ResultType.done) {
      throw Exception('Failed to open installer: ${result.message}');
    }
  }

  /// Version comparison helper
  bool _isNewer({
    required String currentVersion,
    required int currentBuild,
    required String latestVersion,
    required int latestBuild,
  }) {
    if (latestBuild > 0 && currentBuild > 0 && latestBuild > currentBuild) {
      return true;
    }

    final currParts = currentVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final lateParts = latestVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (var i = 0; i < 3; i++) {
      final c = i < currParts.length ? currParts[i] : 0;
      final l = i < lateParts.length ? lateParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }

    return false;
  }
}
