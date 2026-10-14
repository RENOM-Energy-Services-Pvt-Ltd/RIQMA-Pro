import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

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

  static const String _githubLatestReleaseApi =
      'https://api.github.com/repos/RENOM-Energy-Services-Pvt-Ltd/RIQMA-Pro/releases/latest';

  /// Check whether an update is available (from Firestore with GitHub fallback)
  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g. "1.0.0"
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
              headers: {'Accept': 'application/vnd.github.v3+json'},
            )
            .timeout(const Duration(seconds: 6));

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
    try {
      final request = http.Request('GET', Uri.parse(apkUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Download failed with status: ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      var receivedBytes = 0;

      final tempDir = await getTemporaryDirectory();
      final apkFile = File('${tempDir.path}/riqma_update.apk');

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

      // Launch the Android System Package Installer
      final result = await OpenFile.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done) {
        throw Exception('Failed to open installer: ${result.message}');
      }
    } finally {
      client.close();
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
