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
      final canInstall =
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
      final opened =
          await _installerChannel.invokeMethod<bool>('openInstallPermissionSettings');
      return opened ?? false;
    } catch (e) {
      debugPrint('AppUpdateService: Error opening install settings: $e');
      return false;
    }
  }

  /// Open browser to download APK directly
  Future<bool> openBrowser(String url) async {
    try {
      final opened =
          await _installerChannel.invokeMethod<bool>('openBrowser', {'url': url});
      return opened ?? false;
    } catch (e) {
      debugPrint('AppUpdateService: Error opening browser: $e');
      return false;
    }
  }

  /// Get the cached downloaded APK file for a specific target version
  Future<File> getDownloadedApkFile([String? version]) async {
    final tempDir = await getTemporaryDirectory();
    final cleanVersion = (version ?? '').replaceAll('v', '').trim();
    final fileName = cleanVersion.isNotEmpty
        ? 'riqma_update_v$cleanVersion.apk'
        : 'riqma_update.apk';
    return File('${tempDir.path}/$fileName');
  }

  /// Get the partial (.part) download file for resumable downloading
  Future<File> getPartialApkFile([String? version]) async {
    final tempDir = await getTemporaryDirectory();
    final cleanVersion = (version ?? '').replaceAll('v', '').trim();
    final fileName = cleanVersion.isNotEmpty
        ? 'riqma_update_v$cleanVersion.part'
        : 'riqma_update.part';
    return File('${tempDir.path}/$fileName');
  }

  /// Clean obsolete/stale update APK files and partial files from cache
  Future<void> cleanOldApks({String? keepVersion}) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(tempDir.path);
      if (await dir.exists()) {
        final cleanKeep = (keepVersion ?? '').replaceAll('v', '').trim();
        final keepApk = cleanKeep.isNotEmpty ? 'riqma_update_v$cleanKeep.apk' : null;
        final keepPart = cleanKeep.isNotEmpty ? 'riqma_update_v$cleanKeep.part' : null;
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.contains('riqma_update')) {
            final fileName = entity.uri.pathSegments.last;
            if (keepApk != null && (fileName == keepApk || fileName == keepPart)) {
              continue; // Keep current target version files
            }
            try {
              await entity.delete();
              debugPrint('AppUpdateService: Deleted stale file: ${entity.path}');
            } catch (e) {
              debugPrint('AppUpdateService: Error deleting ${entity.path}: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('AppUpdateService: cleanOldApks failed: $e');
    }
  }

  /// Check if the APK for the SPECIFIC target version has already been fully downloaded
  Future<bool> hasDownloadedApk({required String targetVersion}) async {
    try {
      final file = await getDownloadedApkFile(targetVersion);
      if (!await file.exists()) return false;
      final size = await file.length();
      // An APK is at least 20MB. If smaller, it was interrupted.
      if (size < 20 * 1024 * 1024) {
        try {
          await file.delete();
        } catch (_) {}
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Installs an already-downloaded APK after verifying permissions
  Future<void> installDownloadedApk(String targetVersion) async {
    final file = await getDownloadedApkFile(targetVersion);
    if (!await file.exists()) {
      throw Exception('Downloaded update file not found for version $targetVersion.');
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

  /// Downloads APK directly with multi-pass auto-retries, resumable HTTP range chunks, and launches installer
  Future<void> downloadAndInstall({
    required String apkUrl,
    required String targetVersion,
    required void Function(double progress, int receivedBytes, int totalBytes, [String? statusText]) onProgress,
  }) async {
    await cleanOldApks(keepVersion: targetVersion);

    final apkFile = await getDownloadedApkFile(targetVersion);
    final partFile = await getPartialApkFile(targetVersion);

    // If fully downloaded APK already exists and is valid (> 25MB), install directly
    if (await apkFile.exists()) {
      final size = await apkFile.length();
      if (size > 25 * 1024 * 1024) {
        return installDownloadedApk(targetVersion);
      } else {
        try {
          await apkFile.delete();
        } catch (_) {}
      }
    }

    const maxRetries = 10;
    var attempt = 0;
    var totalBytes = 0;

    while (attempt < maxRetries) {
      attempt++;
      HttpClient? client;
      IOSink? sink;

      try {
        client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 45)
          ..idleTimeout = const Duration(seconds: 45);

        var existingBytes = 0;
        if (await partFile.exists()) {
          existingBytes = await partFile.length();
        }

        // Resolve redirects manually to ensure Range header is preserved across CDN domains
        var currentUri = Uri.parse(apkUrl);
        HttpClientResponse? response;

        for (var redirect = 0; redirect < 5; redirect++) {
          final request = await client.getUrl(currentUri);
          request.followRedirects = false;
          request.headers.add('User-Agent', 'RIQMA-Pro-App');
          request.headers.add('Accept', '*/*');

          if (existingBytes > 0) {
            request.headers.add('Range', 'bytes=$existingBytes-');
          }

          response = await request.close();

          if (response.isRedirect) {
            final location = response.headers.value(HttpHeaders.locationHeader);
            if (location == null || location.isEmpty) {
              throw Exception('Redirect location header missing');
            }
            currentUri = Uri.parse(location);
            await response.drain<void>();
          } else {
            break;
          }
        }

        if (response == null) {
          throw Exception('Failed to obtain HTTP response');
        }

        final statusCode = response.statusCode;

        // 416 = Range Not Satisfiable (e.g. corrupt part file or file changed on server)
        if (statusCode == HttpStatus.requestedRangeNotSatisfiable) {
          await response.drain<void>();
          if (await partFile.exists()) {
            await partFile.delete();
          }
          existingBytes = 0;
          continue; // retry fresh from 0
        }

        final isPartial = statusCode == HttpStatus.partialContent;
        if (statusCode != HttpStatus.ok && !isPartial) {
          await response.drain<void>();
          throw Exception('Server returned status $statusCode');
        }

        // Determine total expected size
        if (isPartial) {
          final contentRange = response.headers.value('content-range');
          if (contentRange != null && contentRange.contains('/')) {
            final totalStr = contentRange.split('/').last.trim();
            totalBytes = int.tryParse(totalStr) ?? 0;
          }
          if (totalBytes <= 0 && response.contentLength > 0) {
            totalBytes = existingBytes + response.contentLength;
          }
        } else {
          totalBytes = response.contentLength > 0 ? response.contentLength : 0;
          if (await partFile.exists()) {
            await partFile.delete();
          }
          existingBytes = 0;
        }

        sink = partFile.openWrite(
          mode: isPartial ? FileMode.writeOnlyAppend : FileMode.writeOnly,
        );

        var currentBytes = existingBytes;

        if (totalBytes > 0) {
          final p = (currentBytes / totalBytes).clamp(0.0, 1.0);
          onProgress(p, currentBytes, totalBytes);
        }

        await for (final chunk in response) {
          sink.add(chunk);
          currentBytes += chunk.length;
          if (totalBytes > 0) {
            final p = (currentBytes / totalBytes).clamp(0.0, 1.0);
            onProgress(p, currentBytes, totalBytes);
          }
        }

        await sink.flush();
        await sink.close();
        sink = null;

        final finalSize = await partFile.length();
        if (totalBytes > 0 && finalSize < totalBytes) {
          throw Exception('Stream closed before full download ($finalSize of $totalBytes bytes)');
        }
        if (finalSize < 25 * 1024 * 1024) {
          throw Exception('Downloaded file is unexpectedly small ($finalSize bytes)');
        }

        // Success! Rename .part to final .apk
        if (await apkFile.exists()) {
          await apkFile.delete();
        }
        await partFile.rename(apkFile.path);
        break; // Complete
      } catch (e) {
        debugPrint('AppUpdateService: Download attempt $attempt/$maxRetries error: $e');

        try {
          await sink?.flush();
          await sink?.close();
        } catch (_) {}

        if (attempt >= maxRetries) {
          throw Exception(
            'Download was interrupted due to weak connection. Tap Resume Download to continue.',
          );
        }

        final saved = await partFile.exists() ? await partFile.length() : 0;
        if (totalBytes > 0 && saved > 0) {
          final p = (saved / totalBytes).clamp(0.0, 1.0);
          onProgress(
            p,
            saved,
            totalBytes,
            'Connection dropped. Auto-reconnecting (${attempt + 1}/$maxRetries)...',
          );
        }

        await Future<void>.delayed(Duration(milliseconds: 1500 * attempt));
      } finally {
        client?.close(force: true);
      }
    }

    // Step 2: Verification and installer launch
    await installDownloadedApk(targetVersion);
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
