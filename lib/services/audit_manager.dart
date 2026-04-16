import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuditManager {
  static final AuditManager instance = AuditManager._internal();
  
  factory AuditManager() {
    return instance;
  }

  AuditManager._internal();

  Map<String, dynamic> _localData = {};
  String? _currentDraftId;
  Timer? _debounceTimer;
  bool _isSaving = false;
  bool _hasPendingChanges = false;
  
  // File name based on draft ID
  String get _fileName => _currentDraftId != null ? 'audit_data_$_currentDraftId.json' : 'current_audit_data.json';
  
  // Metadata still uses SharedPreferences for quick access
  String get _metadataKey => _currentDraftId != null ? 'audit_metadata_$_currentDraftId' : 'current_audit_metadata';

  // Expose current draft ID for debugging
  String? get currentDraftId => _currentDraftId;

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
      // SWITCH CONTEXT: New draftId provided
      _currentDraftId = draftId;
      _localData = {}; // Clear to load fresh data for new context
      debugPrint('🔄 AuditManager: Switching context to draftId: $draftId');
    }
    
    // OPTIMIZATION: If data is already loaded and no forceRefresh, skip disk read
    if (_localData.isNotEmpty && !forceRefresh) {
      debugPrint('⚡ AuditManager: Using cached data (${_localData.length} entries)');
      return;
    }

    // Load data from disk
    debugPrint('📂 AuditManager: Loading data from disk for: $_fileName');
    try {
      if (kIsWeb) {
        // Fallback to SharedPreferences for Web
        final prefs = await SharedPreferences.getInstance();
        final jsonString = prefs.getString(_fileName);
        if (jsonString != null) {
          _localData = json.decode(jsonString) as Map<String, dynamic>;
        } else {
          _localData = {};
        }
      } else {
        // Mobile/Desktop: Use File I/O
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$_fileName');
        
        if (await file.exists()) {
          final jsonString = await file.readAsString();
          _localData = json.decode(jsonString) as Map<String, dynamic>;
        } else {
          _localData = {};
        }
      }
      debugPrint('✅ AuditManager: Loaded ${_localData.length} entries');
    } catch (e) {
      debugPrint('❌ AuditManager: Error loading data: $e');
      _localData = {};
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
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final metadata = {
      'siteId': siteId,
      'siteName': siteName,
      'turbineId': turbineId,
      'turbineName': turbineName,
      'stateName': stateName,
      'modelId': modelId,
      'modelName': modelName,
      'timestamp': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_metadataKey, json.encode(metadata));
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
    _localData[taskId] = data;
    _scheduleSave();
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
        if (await file.exists()) {
          await file.delete();
        }
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

  /// Persist current state
  Future<void> _saveData() async {
    if (_isSaving) return;
    
    _isSaving = true;
    _hasPendingChanges = false;
    
    try {
      final jsonString = json.encode(_localData);

      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_fileName, jsonString);
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$_fileName');
        await file.writeAsString(jsonString, flush: true);
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
        await Future<void>.delayed(const Duration(milliseconds: 100));
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
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
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
}
