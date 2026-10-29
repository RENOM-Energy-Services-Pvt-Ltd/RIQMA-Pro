import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuditManager with WidgetsBindingObserver {
  static final AuditManager instance = AuditManager._internal();
  
  factory AuditManager() {
    return instance;
  }

  AuditManager._internal() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      debugPrint('📱 AuditManager: App lifecycle changed to $state -> Flushing pending saves immediately');
      flush();
    }
  }

  Map<String, dynamic> _localData = {};
  String? _currentDraftId;
  Timer? _debounceTimer;
  bool _isSaving = false;
  bool _hasPendingChanges = false;
  Completer<void>? _initCompleter;
  
  // File name based on draft ID
  String get _fileName => _currentDraftId != null ? 'audit_data_$_currentDraftId.json' : 'current_audit_data.json';
  String get _bakFileName => '$_fileName.bak';
  String get _tmpFileName => '$_fileName.tmp';
  
  // Metadata still uses SharedPreferences for quick access
  String get _metadataKey => _currentDraftId != null ? 'audit_metadata_$_currentDraftId' : 'current_audit_metadata';

  // Expose current draft ID for debugging
  String? get currentDraftId => _currentDraftId;

  /// Universal fallback serializer so json.encode NEVER throws JsonUnsupportedObjectError
  static Object? _toEncodable(Object? nonEncodable) {
    if (nonEncodable is DocumentReference) {
      return nonEncodable.path;
    }
    if (nonEncodable is Timestamp) {
      return nonEncodable.toDate().toIso8601String();
    }
    if (nonEncodable is DateTime) {
      return nonEncodable.toIso8601String();
    }
    return nonEncodable?.toString();
  }

  /// Initialize the service and load existing data
  /// 
  /// [draftId] - Optional unique ID for the draft (e.g. "planId_turbineId")
  /// - If draftId is passed: Switch context (update _currentDraftId and load fresh data)
  /// - If draftId is NULL: Preserve context (keep existing _currentDraftId)
  /// 
  /// [forceRefresh] - If true, bypasses memory cache and reloads from disk
  /// Useful for 'Pull to Refresh' scenarios
  Future<void> init({String? draftId, bool forceRefresh = false}) async {
    // Determine if context is changing
    final contextChanged = draftId != null && draftId != _currentDraftId;
    
    if (contextChanged) {
      // PRE-FLUSH: Save any pending changes for the previous draft BEFORE switching context!
      if (_hasPendingChanges || _isSaving) {
        debugPrint('💾 AuditManager: Flushing previous draft ($_currentDraftId) before switching context');
        await flush();
      }
      // SWITCH CONTEXT: New draftId provided
      _currentDraftId = draftId;
      _localData = {}; // Clear to load fresh data for new context
      debugPrint('🔄 AuditManager: Switching context to draftId: $draftId');
    }
    
    // In-flight guard: If an init is already running for this draft, await it
    if (_initCompleter != null && !_initCompleter!.isCompleted) {
      await _initCompleter!.future;
      if (!forceRefresh && _localData.isNotEmpty) {
        return;
      }
    }

    // OPTIMIZATION: If data is already loaded and no forceRefresh, skip disk read
    if (_localData.isNotEmpty && !forceRefresh) {
      debugPrint('⚡ AuditManager: Using cached data (${_localData.length} entries)');
      return;
    }

    _initCompleter = Completer<void>();

    // Load data from disk
    debugPrint('📂 AuditManager: Loading data from disk for: $_fileName');
    try {
      var loaded = false;
      var diskData = <String, dynamic>{};

      if (kIsWeb) {
        // Fallback to SharedPreferences for Web
        final prefs = await SharedPreferences.getInstance();
        final jsonString = prefs.getString(_fileName);
        if (jsonString != null && jsonString.trim().isNotEmpty) {
          try {
            diskData = json.decode(jsonString) as Map<String, dynamic>;
            loaded = true;
          } catch (_) {}
        }
      } else {
        // Mobile/Desktop: Use File I/O with .bak auto-recovery
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$_fileName');
        final bakFile = File('${directory.path}/$_bakFileName');
        
        if (await file.exists()) {
          try {
            final jsonString = await file.readAsString();
            if (jsonString.trim().isNotEmpty) {
              final decoded = json.decode(jsonString);
              if (decoded is Map<String, dynamic>) {
                diskData = decoded;
                loaded = true;
              }
            }
          } catch (e) {
            debugPrint('⚠️ AuditManager: Primary file $_fileName corrupt: $e. Checking backup...');
          }
        }

        // Automatic fallback to .bak if primary was missing or corrupt
        if (!loaded && await bakFile.exists()) {
          try {
            final bakString = await bakFile.readAsString();
            if (bakString.trim().isNotEmpty) {
              final decoded = json.decode(bakString);
              if (decoded is Map<String, dynamic>) {
                diskData = decoded;
                loaded = true;
                debugPrint('🛡️ AuditManager: Successfully restored data from $_bakFileName!');
                try {
                  await file.writeAsString(bakString, flush: true);
                } catch (_) {}
              }
            }
          } catch (e) {
            debugPrint('❌ AuditManager: Error reading backup draft file: $e');
          }
        }
      }

      _localData = diskData;

      // Normalize any corrected tasks to strictly 'Not OK'
      _localData.forEach((key, val) {
        if (val is Map && val['is_corrected'] == true) {
          val['status'] = 'Not OK';
        }
      });

      // AUTO-RECOVERY & HYBRID MERGING:
      // If user filled some answers online (planId_turbineId) and some offline (unplanned_turbineId),
      // merge complementary answers so data is NEVER wiped!
      await _mergeComplementaryDraftIfAvailable();

      debugPrint('✅ AuditManager: Loaded ${_localData.length} entries');
    } catch (e) {
      debugPrint('❌ AuditManager: Error loading data: $e');
      _localData = {};
    } finally {
      if (_initCompleter != null && !_initCompleter!.isCompleted) {
        _initCompleter!.complete();
      }
    }
  }

  /// Automatically merge complementary drafts for the same turbine (e.g. unplanned_T01 and planId_T01)
  /// to support seamless hybrid online/offline audits without any data wipe.
  Future<void> _mergeComplementaryDraftIfAvailable() async {
    if (_currentDraftId == null || _currentDraftId == 'current') return;

    final parts = _currentDraftId!.split('_');
    if (parts.length < 2) return;
    final turbineId = parts.sublist(1).join('_');
    if (turbineId.isEmpty) return;

    final complementaryDraftIds = <String>{};
    if (_currentDraftId!.startsWith('unplanned_')) {
      // Current is unplanned; search prefs for any planId_turbineId
      try {
        final prefs = await SharedPreferences.getInstance();
        for (final key in prefs.getKeys()) {
          if (key.startsWith('audit_metadata_') && key.endsWith('_$turbineId')) {
            final cId = key.replaceFirst('audit_metadata_', '');
            if (cId != _currentDraftId && !cId.startsWith('unplanned_')) {
              complementaryDraftIds.add(cId);
            }
          }
        }
      } catch (_) {}
    } else {
      // Current is planned; check if unplanned_turbineId exists
      complementaryDraftIds.add('unplanned_$turbineId');
    }

    if (complementaryDraftIds.isEmpty) return;

    for (final cId in complementaryDraftIds) {
      try {
        Map<String, dynamic>? cData;
        if (kIsWeb) {
          final prefs = await SharedPreferences.getInstance();
          final s = prefs.getString('audit_data_$cId.json');
          if (s != null && s.trim().isNotEmpty) {
            cData = json.decode(s) as Map<String, dynamic>?;
          }
        } else {
          final directory = await getApplicationDocumentsDirectory();
          final cFile = File('${directory.path}/audit_data_$cId.json');
          if (await cFile.exists()) {
            final s = await cFile.readAsString();
            if (s.trim().isNotEmpty) {
              cData = json.decode(s) as Map<String, dynamic>?;
            }
          }
        }

        if (cData != null && cData.isNotEmpty) {
          var anyMerged = false;
          cData.forEach((taskId, taskVal) {
            if (taskVal is Map) {
              final map = Map<String, dynamic>.from(taskVal);
              if (!_localData.containsKey(taskId)) {
                _localData[taskId] = map;
                anyMerged = true;
              } else {
                final existing = _localData[taskId] as Map<String, dynamic>?;
                final existingStatus = existing?['status'];
                final newStatus = map['status'];
                if ((existingStatus == null || existingStatus.toString().isEmpty) &&
                    (newStatus != null && newStatus.toString().isNotEmpty)) {
                  _localData[taskId] = map;
                  anyMerged = true;
                }
              }
            }
          });

          if (anyMerged) {
            debugPrint('🤝 AuditManager: Seamlessly merged complementary answers from $cId for turbine $turbineId');
            _scheduleSave();
          }
        }
      } catch (e) {
        debugPrint('AuditManager: Error checking complementary draft $cId: $e');
      }
    }
  }

  /// Clear the current audit session from memory
  /// 
  /// This does NOT delete persisted data on disk - use [clearAudit] for that.
  /// Use this to free memory when:
  /// - User returns to dashboard
  /// - After successful audit submission
  /// - When switching between different features
  void clearSession() {
    _currentDraftId = null;
    _localData = {};
    _debounceTimer?.cancel();
    _hasPendingChanges = false;
    debugPrint('🧹 Audit Session Cleared - Memory Freed');
  }

  /// Save draft metadata (context like site, turbine, etc.)
  Future<void> saveDraftMetadata({
    required String siteId,
    required String siteName,
    required String turbineId,
    required String turbineName,
    required String stateName,
    required String modelId,
    required String modelName,
    String? draftId,
    String? planId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final effectiveDraftId = draftId ?? _currentDraftId ?? '${planId ?? "unplanned"}_$turbineId';
    final metadata = {
      'siteId': siteId,
      'siteName': siteName,
      'turbineId': turbineId,
      'turbineName': turbineName,
      'stateName': stateName,
      'modelId': modelId,
      'modelName': modelName,
      'planId': planId,
      'timestamp': DateTime.now().toIso8601String(),
    };
    await prefs.setString('audit_metadata_$effectiveDraftId', json.encode(metadata));
    if (_currentDraftId == null && (planId == null || planId == 'unplanned')) {
      await prefs.setString('current_audit_metadata', json.encode(metadata));
    }
  }

  /// Get draft metadata
  Future<Map<String, dynamic>?> getDraftMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_metadataKey);
    if (jsonString != null) {
      try {
        return json.decode(jsonString) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error decoding draft metadata: $e');
        return null;
      }
    }
    return null;
  }

  /// Check if a draft exists
  Future<bool> hasDraft() async {
    final prefs = await SharedPreferences.getInstance();
    // We check metadata existence as a proxy for draft existence
    return prefs.containsKey(_metadataKey);
  }

  /// Save an answer for a specific task
  void saveAnswer(String taskId, Map<String, dynamic> data) {
    final sanitizedData = Map<String, dynamic>.from(data);
    if (sanitizedData['is_corrected'] == true) {
      sanitizedData['status'] = 'Not OK';
    }
    // Deep sanitize any DocumentReference or non-serializable objects
    sanitizedData.forEach((key, val) {
      if (val is DocumentReference) {
        sanitizedData[key] = val.path;
      }
    });
    _localData[taskId] = sanitizedData;
    _scheduleSave();
    _touchMetadataTimestamp();
  }

  void _touchMetadataTimestamp() {
    if (_currentDraftId == null) return;
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = 'audit_metadata_$_currentDraftId';
        final existing = prefs.getString(key);
        if (existing != null) {
          final map = json.decode(existing) as Map<String, dynamic>;
          map['timestamp'] = DateTime.now().toIso8601String();
          await prefs.setString(key, json.encode(map));
        }
      } catch (_) {}
    }());
  }

  /// Schedules a debounced save operation
  void _scheduleSave() {
    _hasPendingChanges = true;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _saveData();
    });
  }

  /// Get saved answer for a specific task
  Map<String, dynamic>? getAnswer(String taskId) {
    return _localData[taskId] as Map<String, dynamic>?;
  }

  /// Get all saved answers
  Map<String, dynamic> getAllAnswers() {
    return Map<String, dynamic>.from(_localData);
  }

  /// Clear all saved audit data (from memory AND disk)
  /// 
  /// Use this after successful submission to clean up completely.
  /// For memory-only cleanup, use [clearSession] instead.
  Future<void> clearAudit() async {
    _localData.clear();
    
    // Clear Data File
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_fileName);
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$_fileName');
        final bakFile = File('${directory.path}/$_bakFileName');
        final tmpFile = File('${directory.path}/$_tmpFileName');
        if (await file.exists()) await file.delete();
        if (await bakFile.exists()) await bakFile.delete();
        if (await tmpFile.exists()) await tmpFile.delete();
      }
    } catch (e) {
      debugPrint('Error clearing audit file: $e');
    }

    // Clear Metadata
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_metadataKey);
    
    // Also clear session state
    _currentDraftId = null;
    _debounceTimer?.cancel();
    _hasPendingChanges = false;
    debugPrint('🗑️ Audit Data Cleared (Memory + Disk)');
  }

  /// Persist current state with atomic write and safe JSON encoding
  Future<void> _saveData() async {
    if (_isSaving) return;
    
    _isSaving = true;
    _hasPendingChanges = false;
    
    try {
      final jsonString = json.encode(_localData, toEncodable: _toEncodable);

      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_fileName, jsonString);
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final finalFile = File('${directory.path}/$_fileName');
        final tmpFile = File('${directory.path}/$_tmpFileName');
        final bakFile = File('${directory.path}/$_bakFileName');

        // 1. Write to temp file first with OS flush
        await tmpFile.writeAsString(jsonString, flush: true);

        // 2. Backup current final file before replacement
        if (await finalFile.exists()) {
          try {
            await finalFile.copy(bakFile.path);
          } catch (_) {}
        }

        // 3. Atomically replace final file
        if (await tmpFile.exists()) {
          try {
            if (await finalFile.exists()) {
              await finalFile.delete();
            }
            await tmpFile.rename(finalFile.path);
          } catch (_) {
            await tmpFile.copy(finalFile.path);
            try {
              await tmpFile.delete();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('Error saving audit data: $e');
      _hasPendingChanges = true; // Mark as needs retry if failed
    } finally {
      _isSaving = false;
      // If changes occurred while saving, schedule another save
      if (_hasPendingChanges) {
        _scheduleSave();
      }
    }
  }

  /// Ensure all pending changes are saved (useful before exiting or submitting)
  Future<void> flush() async {
    _debounceTimer?.cancel();
    if (_hasPendingChanges || _isSaving) {
      // If already saving, wait for it and then check if more changes were made
      while (_isSaving) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (_hasPendingChanges) {
        await _saveData();
      }
    }
  }

  /// Check if a specific draft ID has existing data without loading it into memory
  static Future<bool> draftExists(String draftId) async {
    final fileName = 'audit_data_$draftId.json';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey('audit_metadata_$draftId')) return true;

      if (kIsWeb) {
        return prefs.containsKey(fileName);
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$fileName');
        return await file.exists();
      }
    } catch (e) {
      return false;
    }
  }

  /// Get all local drafts as rich summaries by scanning both Disk and SharedPreferences
  Future<List<DraftAuditSummary>> getAllIncompleteAudits() async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();

    // Set of all discovered unique draft IDs
    final discoveredDraftIds = <String>{};

    // 1. Discover from SharedPreferences metadata keys
    for (var key in allKeys) {
      if (key.startsWith('audit_metadata_')) {
        final dId = key.replaceFirst('audit_metadata_', '');
        if (dId.isNotEmpty) discoveredDraftIds.add(dId);
      } else if (key == 'current_audit_metadata') {
        discoveredDraftIds.add('current');
      }
    }

    // 2. Discover from File System (Mobile / Desktop)
    final fileMap = <String, File>{};
    if (!kIsWeb) {
      try {
        final directory = await getApplicationDocumentsDirectory();
        final entities = directory.listSync();
        for (var entity in entities) {
          if (entity is File) {
            final fileName = p.basename(entity.path);
            if (fileName.startsWith('audit_data_') && fileName.endsWith('.json')) {
              final dId = fileName.substring('audit_data_'.length, fileName.length - '.json'.length);
              if (dId.isNotEmpty) {
                discoveredDraftIds.add(dId);
                fileMap[dId] = entity;
              }
            } else if (fileName == 'current_audit_data.json') {
              discoveredDraftIds.add('current');
              fileMap['current'] = entity;
            }
          }
        }
      } catch (e) {
        debugPrint('Error scanning directory for drafts: $e');
      }
    } else {
      // For Web, scan prefs for data files
      for (var key in allKeys) {
        if (key.startsWith('audit_data_') && key.endsWith('.json')) {
          final dId = key.substring('audit_data_'.length, key.length - '.json'.length);
          if (dId.isNotEmpty) discoveredDraftIds.add(dId);
        } else if (key == 'current_audit_data.json') {
          discoveredDraftIds.add('current');
        }
      }
    }

    final summaries = <DraftAuditSummary>[];

    for (var draftId in discoveredDraftIds) {
      try {
        // Load metadata
        Map<String, dynamic>? meta;
        final metaKey = draftId == 'current' ? 'current_audit_metadata' : 'audit_metadata_$draftId';
        final metaStr = prefs.getString(metaKey);
        if (metaStr != null) {
          try {
            meta = json.decode(metaStr) as Map<String, dynamic>?;
          } catch (_) {}
        }

        // Load audit answers data
        var answers = <String, dynamic>{};
        DateTime? lastModified;

        if (kIsWeb) {
          final dataKey = draftId == 'current' ? 'current_audit_data.json' : 'audit_data_$draftId.json';
          final dataStr = prefs.getString(dataKey);
          if (dataStr != null) {
            try {
              answers = json.decode(dataStr) as Map<String, dynamic>;
            } catch (_) {}
          }
        } else {
          var targetFile = fileMap[draftId];
          if (targetFile == null) {
            final directory = await getApplicationDocumentsDirectory();
            final fileName = draftId == 'current' ? 'current_audit_data.json' : 'audit_data_$draftId.json';
            targetFile = File('${directory.path}/$fileName');
          }

          if (await targetFile.exists()) {
            lastModified = await targetFile.lastModified();
            try {
              final content = await targetFile.readAsString();
              if (content.trim().isNotEmpty) {
                final decoded = json.decode(content);
                if (decoded is Map<String, dynamic>) {
                  answers = decoded;
                }
              }
            } catch (e) {
              debugPrint('Error reading draft file for $draftId: $e');
            }
          }
        }

        // Calculate statistics from answers
        var okCount = 0;
        var notOkCount = 0;
        var naCount = 0;
        var observationCount = 0;
        var photoCount = 0;
        final photoPaths = <String>[];

        for (var taskEntry in answers.values) {
          if (taskEntry is Map<String, dynamic>) {
            final status = taskEntry['status']?.toString().trim().toLowerCase();
            if (status == 'ok') {
              okCount++;
            } else if (status == 'not ok') {
              notOkCount++;
            } else if (status == 'n/a' || status == 'na') {
              naCount++;
            }

            final obs = taskEntry['observation']?.toString().trim();
            if (obs != null && obs.isNotEmpty) {
              observationCount++;
            }

            final photos = taskEntry['photos'];
            if (photos is List) {
              photoCount += photos.length;
              for (var p in photos) {
                if (p is String && p.isNotEmpty) photoPaths.add(p);
              }
            }

            final closurePhoto = taskEntry['closure_photo_local_path'];
            if (closurePhoto is String && closurePhoto.isNotEmpty) {
              photoCount++;
              photoPaths.add(closurePhoto);
            }
          }
        }

        // Determine timestamp
        DateTime? lastSaved;
        if (meta?['timestamp'] != null) {
          try {
            lastSaved = DateTime.parse(meta!['timestamp'] as String);
          } catch (_) {}
        }
        if (lastSaved == null || (lastModified != null && lastModified.isAfter(lastSaved))) {
          lastSaved = lastModified ?? lastSaved;
        }

        // Determine turbine & site names
        var turbineName = meta?['turbineName']?.toString() ?? '';
        var turbineId = meta?['turbineId']?.toString() ?? '';
        final siteName = meta?['siteName']?.toString() ?? '';
        final siteId = meta?['siteId']?.toString() ?? '';
        final stateName = meta?['stateName']?.toString() ?? '';
        final modelName = meta?['modelName']?.toString() ?? '';
        var planId = meta?['planId']?.toString();

        final isUnplanned = draftId.startsWith('unplanned_') || draftId == 'unplanned' || draftId == 'current' || (planId == null || planId.isEmpty);

        if (turbineName.isEmpty || turbineId.isEmpty) {
          final parts = draftId.split('_');
          if (parts.length >= 2) {
            if (parts[0] != 'unplanned' && planId == null) {
              planId = parts[0];
            }
            turbineId = parts.sublist(1).join('_');
            turbineName = 'Turbine $turbineId';
          } else {
            turbineName = draftId == 'current' ? 'Current Incomplete Audit' : 'Incomplete Audit ($draftId)';
          }
        }

        summaries.add(DraftAuditSummary(
          draftId: draftId,
          turbineName: turbineName,
          turbineId: turbineId,
          siteName: siteName.isNotEmpty ? siteName : 'Local Storage',
          siteId: siteId,
          stateName: stateName,
          modelName: modelName,
          planId: planId,
          lastSaved: lastSaved,
          totalTasksAnswered: answers.length,
          okCount: okCount,
          notOkCount: notOkCount,
          naCount: naCount,
          observationCount: observationCount,
          photoCount: photoCount,
          photoPaths: photoPaths,
          isUnplanned: isUnplanned,
        ));
      } catch (e) {
        debugPrint('Error processing draft $draftId: $e');
      }
    }

    // Sort newest first
    summaries.sort((a, b) {
      if (a.lastSaved == null && b.lastSaved == null) return 0;
      if (a.lastSaved == null) return 1;
      if (b.lastSaved == null) return -1;
      return b.lastSaved!.compareTo(a.lastSaved!);
    });

    return summaries;
  }

  /// Get all local drafts metadata (legacy compatibility)
  Future<List<Map<String, dynamic>>> getAllDraftsMetadata() async {
    final drafts = await getAllIncompleteAudits();
    return drafts.map((d) => d.toMap()).toList();
  }

  /// Delete a specific draft from disk and SharedPreferences, including local photos
  Future<void> deleteDraft(String draftId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Remove Metadata
      await prefs.remove('audit_metadata_$draftId');
      if (draftId == 'current' || draftId == 'unplanned') {
        await prefs.remove('current_audit_metadata');
      }

      // 2. Remove Data File & Clean up local photos
      final fileName = 'audit_data_$draftId.json';
      if (kIsWeb) {
        await prefs.remove(fileName);
        if (draftId == 'current' || draftId == 'unplanned') {
          await prefs.remove('current_audit_data.json');
        }
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$fileName');

        Future<void> cleanUpPhotos(File f) async {
          try {
            final content = await f.readAsString();
            if (content.trim().isNotEmpty) {
              final decoded = json.decode(content);
              if (decoded is Map<String, dynamic>) {
                for (var taskEntry in decoded.values) {
                  if (taskEntry is Map<String, dynamic>) {
                    final photos = taskEntry['photos'];
                    if (photos is List) {
                      for (var p in photos) {
                        if (p is String && !p.startsWith('http')) {
                          try {
                            final photoFile = File(p);
                            if (await photoFile.exists()) {
                              await photoFile.delete();
                            }
                          } catch (_) {}
                        }
                      }
                    }
                    final closurePhoto = taskEntry['closure_photo_local_path'];
                    if (closurePhoto is String && !closurePhoto.startsWith('http')) {
                      try {
                        final photoFile = File(closurePhoto);
                        if (await photoFile.exists()) {
                          await photoFile.delete();
                        }
                      } catch (_) {}
                    }
                  }
                }
              }
            }
          } catch (e) {
            debugPrint('Error cleaning up draft photos: $e');
          }
        }

        final bakFile = File('${directory.path}/$fileName.bak');
        final tmpFile = File('${directory.path}/$fileName.tmp');
        if (await bakFile.exists()) await bakFile.delete();
        if (await tmpFile.exists()) await tmpFile.delete();

        if (await file.exists()) {
          await cleanUpPhotos(file);
          await file.delete();
        }

        if (draftId == 'current' || draftId == 'unplanned') {
          final curFile = File('${directory.path}/current_audit_data.json');
          final curBak = File('${directory.path}/current_audit_data.json.bak');
          final curTmp = File('${directory.path}/current_audit_data.json.tmp');
          if (await curBak.exists()) await curBak.delete();
          if (await curTmp.exists()) await curTmp.delete();
          if (await curFile.exists()) {
            await cleanUpPhotos(curFile);
            await curFile.delete();
          }
        }
      }

      // 3. If it was the current session, clear it
      if (_currentDraftId == draftId || (draftId == 'current' && _currentDraftId == null)) {
        clearSession();
      }

      debugPrint('🗑️ Draft $draftId deleted successfully');
    } catch (e) {
      debugPrint('❌ Error deleting draft $draftId: $e');
      rethrow;
    }
  }
}

/// Rich summary representation of an incomplete/pending audit draft
class DraftAuditSummary {
  final String draftId;
  final String turbineName;
  final String turbineId;
  final String siteName;
  final String siteId;
  final String stateName;
  final String modelName;
  final String? planId;
  final DateTime? lastSaved;
  final int totalTasksAnswered;
  final int okCount;
  final int notOkCount;
  final int naCount;
  final int observationCount;
  final int photoCount;
  final List<String> photoPaths;
  final bool isUnplanned;

  DraftAuditSummary({
    required this.draftId,
    required this.turbineName,
    required this.turbineId,
    required this.siteName,
    required this.siteId,
    required this.stateName,
    required this.modelName,
    this.planId,
    this.lastSaved,
    this.totalTasksAnswered = 0,
    this.okCount = 0,
    this.notOkCount = 0,
    this.naCount = 0,
    this.observationCount = 0,
    this.photoCount = 0,
    this.photoPaths = const [],
    this.isUnplanned = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'draft_id': draftId,
      'turbineName': turbineName,
      'turbineId': turbineId,
      'siteName': siteName,
      'siteId': siteId,
      'stateName': stateName,
      'modelName': modelName,
      'planId': planId,
      'timestamp': lastSaved?.toIso8601String(),
      'totalTasksAnswered': totalTasksAnswered,
      'okCount': okCount,
      'notOkCount': notOkCount,
      'naCount': naCount,
      'observationCount': observationCount,
      'photoCount': photoCount,
      'photoPaths': photoPaths,
      'isUnplanned': isUnplanned,
    };
  }
}
