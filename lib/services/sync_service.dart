import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Service responsible for proactive deep offline syncing of audit data.
/// It ensures that all checklists, tasks, and master data for approved plans
/// are "pre-warmed" in the Firestore local cache.
class SyncService extends ChangeNotifier {
  static final SyncService instance = SyncService._();
  SyncService._();

  bool _isSyncing = false;
  bool _isReady = false;
  double _progress = 0;
  String? _statusMessage;
  StreamSubscription? _plansSubscription;

  bool get isSyncing => _isSyncing;
  bool get isReady => _isReady;
  double get progress => _progress;
  String? get statusMessage => _statusMessage;

  /// Starts the proactive sync process. 
  /// Should be called after the user is authenticated.
  void startSync() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_isSyncing) return;

    _isSyncing = true;
    _statusMessage = 'Identifying plans...';
    notifyListeners();

    // Listen to approved plans to know what to sync
    _plansSubscription?.cancel();
    _plansSubscription = FirebaseFirestore.instance
        .collection('planning_data')
        .where('auditor_id', isEqualTo: user.uid)
        .where('status', isEqualTo: 'approved')
        .snapshots()
        .listen((snapshot) {
      _performDeepSync(snapshot.docs);
    });
  }

  Future<void> _performDeepSync(List<QueryDocumentSnapshot> planDocs) async {
    try {
      _isSyncing = true;
      _isReady = false;
      _progress = 0.1;
      _statusMessage = 'Syncing master data...';
      notifyListeners();

      // 1. Sync Master Data (needed for the selection wizard)
      await Future.wait([
        FirebaseFirestore.instance.collection('states').get(),
        FirebaseFirestore.instance.collection('sites').get(),
        FirebaseFirestore.instance.collection('turbinemodel').get(),
        FirebaseFirestore.instance.collection('turbinename').get(),
        FirebaseFirestore.instance.collection('audit_configs').get(),
      ]);

      _progress = 0.3;
      _statusMessage = 'Syncing checklists...';
      notifyListeners();

      // 2. Identify unique turbine models from plans
      final modelIds = <String>{};
      for (var doc in planDocs) {
        final data = doc.data() as Map<String, dynamic>;
        final modelRef = data['turbine_model_ref'] as DocumentReference?;
        if (modelRef != null) {
          modelIds.add(modelRef.id);
        }
      }

      if (modelIds.isEmpty) {
        _isSyncing = false;
        _isReady = true;
        _progress = 1.0;
        _statusMessage = 'Offline Ready (No plans found)';
        notifyListeners();
        return;
      }

      // 3. Deep sync each model
      var processedModels = 0;
      for (var modelId in modelIds) {
        _statusMessage = 'Syncing model ($processedModels/${modelIds.length})...';
        notifyListeners();

        // Fetch Main Categories for this model
        final mainCats = await FirebaseFirestore.instance
            .collection('main_categories')
            .where('target_models', arrayContains: modelId)
            .get();
        
        // Also fetch "All Models" categories
        final allModelCats = await FirebaseFirestore.instance
            .collection('main_categories')
            .where('is_all_models', isEqualTo: true)
            .get();

        final combinedCats = [...mainCats.docs, ...allModelCats.docs];

        // Deep fetch Subcategories and Tasks
        for (var cat in combinedCats) {
          final subCats = await FirebaseFirestore.instance
              .collection('sub_categories')
              .where('main_categories_ref', isEqualTo: cat.reference)
              .get();

          for (var subCat in subCats.docs) {
             // Fetching tasks ensures they are in cache for Search and Audit
             await FirebaseFirestore.instance
                .collection('tasks')
                .where('sub_categories_ref', isEqualTo: subCat.reference)
                .get();
          }
        }

        processedModels++;
        _progress = 0.3 + (0.7 * (processedModels / modelIds.length));
        notifyListeners();
      }

      _isSyncing = false;
      _isReady = true;
      _progress = 1.0;
      _statusMessage = 'Offline Ready';
      notifyListeners();

    } catch (e) {
      _isSyncing = false;
      _statusMessage = 'Sync failed. Retry on reconnection.';
      debugPrint('Sync Error: $e');
      notifyListeners();
    }
  }

  void stopSync() {
    _plansSubscription?.cancel();
    _isSyncing = false;
    _isReady = false;
    notifyListeners();
  }
}
