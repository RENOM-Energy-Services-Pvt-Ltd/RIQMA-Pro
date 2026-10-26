import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/audit_manager.dart';
import '../widgets/audit_card_widget.dart';
import 'audit/add_new_nc_screen.dart';
import 'audit_task_screen.dart';

class AuditSubCategoriesScreen extends StatefulWidget {
  final String parentCategoryName;
  final DocumentReference mainCategoryRef;
  final DocumentReference turbineModelRef;
  final String? turbineId;
  final String? draftId;

  const AuditSubCategoriesScreen({
    required this.parentCategoryName, required this.mainCategoryRef, required this.turbineModelRef, super.key,
    this.turbineId,
    this.draftId,
  });

  @override
  State<AuditSubCategoriesScreen> createState() => _AuditSubCategoriesScreenState();
}

class _AuditSubCategoriesScreenState extends State<AuditSubCategoriesScreen> {
  // Merged result list
  final List<QueryDocumentSnapshot> _subCategories = [];
  StreamSubscription<QuerySnapshot>? _subByModel;
  StreamSubscription<QuerySnapshot>? _subAllModels;

  // Track doc IDs for merging
  final Set<String> _modelDocIds = {};
  final Set<String> _allModelsDocIds = {};
  bool _isLoading = true; // Track loading state

  // Cached task IDs & calculated progress stats per sub-category
  final Map<String, List<String>> _subCategoryTaskIds = {};
  final Map<String, Map<String, int>> _subCategoryStats = {};
  int _statsLoadSession = 0;

  @override
  void initState() {
    super.initState();
    _subscribeToSubCategories();
  }

  @override
  void dispose() {
    _subByModel?.cancel();
    _subAllModels?.cancel();
    super.dispose();
  }

  void _subscribeToSubCategories() {
    // Stream 1: Sub-categories for this specific turbine model property target_models
    _subByModel = FirebaseFirestore.instance
        .collection('sub_categories')
        .where('main_categories_ref', isEqualTo: widget.mainCategoryRef)
        .where('target_models', arrayContains: widget.turbineModelRef.id)
        // orderBy removed to bypass composite index requirement; local sorting handles this
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      _modelDocIds
        ..clear()
        ..addAll(snapshot.docs.map((d) => d.id));
      _mergeSubCategories(stream1Docs: snapshot.docs);
    }, onError: (Object e) {
      debugPrint('sub_categories target_models query failed: $e');
      // If index is missing, fall back to legacy query (ignore target_models)
      _subscribeToLegacyStream();
    });

    // Stream 2: Sub-categories marked for ALL models
    _subAllModels = FirebaseFirestore.instance
        .collection('sub_categories')
        .where('main_categories_ref', isEqualTo: widget.mainCategoryRef)
        .where('is_all_models', isEqualTo: true)
        // orderBy removed to bypass composite index requirement; local sorting handles this
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      _allModelsDocIds
        ..clear()
        ..addAll(snapshot.docs.map((d) => d.id));
      _mergeSubCategories(stream2Docs: snapshot.docs);
    }, onError: (Object e) {
      debugPrint('sub_categories is_all_models query failed: $e');
      // Ensure loading state is cleared even if this stream fails
      if (mounted && _subCategories.isEmpty) setState(() => _isLoading = false);
    });
  }

  void _subscribeToLegacyStream() {
    _subByModel?.cancel();
    _subAllModels?.cancel(); // Cancel the all-models stream too since it also failed
    _subByModel = FirebaseFirestore.instance
        .collection('sub_categories')
        .where('main_categories_ref', isEqualTo: widget.mainCategoryRef)
        // orderBy removed to bypass composite index requirement; local sorting handles this
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      _subCategories
        ..clear()
        ..addAll(snapshot.docs);
      if (_subCategories.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
      } else {
        _loadAllSubCategoryStats();
      }
    }, onError: (Object e) {
      debugPrint('sub_categories legacy query also failed: $e');
      if (mounted) setState(() => _isLoading = false);
    });
  }

  void _mergeSubCategories({
    List<QueryDocumentSnapshot>? stream1Docs,
    List<QueryDocumentSnapshot>? stream2Docs,
  }) {
    final merged = <String, QueryDocumentSnapshot>{};

    // Restore from existing state
    for (final doc in _subCategories) {
      merged[doc.id] = doc;
    }

    if (stream1Docs != null) {
      for (final doc in stream1Docs) {
        merged[doc.id] = doc;
      }
      for (final id in Set<String>.from(_modelDocIds)) {
        if (!stream1Docs.any((d) => d.id == id)) {
          merged.remove(id);
        }
      }
    }

    if (stream2Docs != null) {
      for (final doc in stream2Docs) {
        merged[doc.id] = doc;
      }
      for (final id in Set<String>.from(_allModelsDocIds)) {
        if (!stream2Docs.any((d) => d.id == id)) {
          merged.remove(id);
        }
      }
    }

    // Sort combined results
    final sorted = merged.values.toList()
      ..sort((a, b) {
        final aOrder = (a.data() as Map<String, dynamic>)['sort_order'] ?? 0;
        final bOrder = (b.data() as Map<String, dynamic>)['sort_order'] ?? 0;
        return (aOrder as num).compareTo(bOrder as num);
      });

    _subCategories
      ..clear()
      ..addAll(sorted);

    if (_subCategories.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
    } else {
      _loadAllSubCategoryStats();
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48.0),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF00897B), Color(0xFF1565C0)], // Green to Blue
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: AppBar(
            toolbarHeight: 48.0,
            backgroundColor: Colors.transparent,
            elevation: 0,
            systemOverlayStyle: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness: Brightness.dark,
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              widget.parentCategoryName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_task_rounded, color: Colors.white),
                tooltip: 'Add New NC',
                onPressed: _openCustomSubCatModal,
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? GridView.builder(
              padding: const EdgeInsets.all(16.0),
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.02,
              ),
              itemCount: 4,
              itemBuilder: (context, index) => const AuditCardSkeleton(),
            )
          : _subCategories.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.list_alt_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 16),
                      Text('No sub-categories found', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('Check "target_models" for this model', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
                    ],
                  ),
                )
          : GridView.builder(
              padding: const EdgeInsets.all(16.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.90, // Spacious for card height with Add New NC button
              ),
              itemCount: _subCategories.length,
              itemBuilder: (context, index) {
                final doc = _subCategories[index];
                final data = doc.data() as Map<String, dynamic>;
                final categoryName = (data['name'] as String?) ?? 'Unknown';

                final stats = _subCategoryStats[doc.id] ?? {'total': 0, 'ok': 0, 'notOk': 0, 'na': 0};
                final total = stats['total'] ?? 0;
                final ok = stats['ok'] ?? 0;
                final notOk = stats['notOk'] ?? 0;
                final na = stats['na'] ?? 0;
                final completed = ok + notOk + na;
                final pending = total - completed;

                return AuditCard(
                  title: categoryName,
                  total: total,
                  ok: ok,
                  notOk: notOk,
                  pending: pending,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (context) => AuditTaskScreen(
                          subCategoryName: categoryName,
                          subCategoryRef: doc.reference,
                          mainCategoryName: widget.parentCategoryName,
                          mainCategoryRef: widget.mainCategoryRef,
                          turbineId: widget.turbineId,
                          draftId: widget.draftId,
                        ),
                      ),
                    ).then((_) => _recalculateStatsFromLocal());
                  },
                  onAddNewNc: () => _openAddNewNcForSubCat(doc),
                );
              },
            ),
    );
  }

  /// Concurrently loads tasks for all sub-categories so all cards appear at once.
  Future<void> _loadAllSubCategoryStats() async {
    final sessionId = ++_statsLoadSession;
    if (widget.draftId != null) {
      await AuditManager.instance.init(draftId: widget.draftId);
    }
    final allAnswers = AuditManager.instance.getAllAnswers();

    try {
      final taskSnapshots = await Future.wait(
        _subCategories.map((doc) => FirebaseFirestore.instance
            .collection('tasks')
            .where('sub_categories_ref', isEqualTo: doc.reference)
            .get()),
      );

      if (!mounted || sessionId != _statsLoadSession) return;

      final newStats = <String, Map<String, int>>{};
      for (var i = 0; i < _subCategories.length; i++) {
        final doc = _subCategories[i];
        final subCatId = doc.id;
        final subCatName = (doc.data() as Map<String, dynamic>)['name']?.toString() ?? '';
        final taskIds = taskSnapshots[i].docs.map((d) => d.id).toList();
        _subCategoryTaskIds[subCatId] = taskIds;
        newStats[subCatId] = _computeStatsFromTaskIds(subCatId, subCatName, taskIds, allAnswers);
      }

      setState(() {
        _subCategoryStats.addAll(newStats);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading sub-category stats: $e');
      if (mounted && sessionId == _statsLoadSession) {
        setState(() => _isLoading = false);
      }
    }
  }

  Map<String, int> _computeStatsFromTaskIds(String subCatId, String subCatName, List<String> taskIds, Map<String, dynamic> allAnswers) {
    var okCount = 0;
    var notOkCount = 0;
    var naCount = 0;
    var customCount = 0;

    for (final taskId in taskIds) {
      if (allAnswers.containsKey(taskId)) {
        final answerData = allAnswers[taskId] as Map<String, dynamic>?;
        final status = answerData?['status'];
        if (status == 'OK') {
          okCount++;
        } else if (status == 'Not OK') {
          notOkCount++;
        } else if (status == 'NA') {
          naCount++;
        }
      }
    }

    // Include custom NCs for this sub-category
    for (final entry in allAnswers.entries) {
      final taskId = entry.key;
      if (taskIds.contains(taskId)) continue;
      final taskData = entry.value as Map<String, dynamic>?;
      if (taskData == null) continue;
      final isForSubCat = taskData['sub_category_id'] == subCatId ||
          (taskData['sub_category_name'] == subCatName && taskData['main_category_id'] == widget.mainCategoryRef.id);
      if (isForSubCat) {
        customCount++;
        final status = taskData['status'];
        if (status == 'OK') {
          okCount++;
        } else if (status == 'Not OK') {
          notOkCount++;
        } else if (status == 'NA') {
          naCount++;
        }
      }
    }

    return {'total': taskIds.length + customCount, 'ok': okCount, 'notOk': notOkCount, 'na': naCount};
  }

  void _recalculateStatsFromLocal() {
    final allAnswers = AuditManager.instance.getAllAnswers();
    setState(() {
      for (var i = 0; i < _subCategories.length; i++) {
        final doc = _subCategories[i];
        final subCatId = doc.id;
        final subCatName = (doc.data() as Map<String, dynamic>)['name']?.toString() ?? '';
        final taskIds = _subCategoryTaskIds[subCatId] ?? [];
        _subCategoryStats[subCatId] = _computeStatsFromTaskIds(subCatId, subCatName, taskIds, allAnswers);
      }
    });
  }

  Future<void> _openAddNewNcForSubCat(QueryDocumentSnapshot subDoc) async {
    final data = subDoc.data() as Map<String, dynamic>;
    final subCatName = (data['name'] as String?) ?? 'Unknown Sub-Category';
    var ref = data['default_reference']?.toString() ?? data['reference']?.toString();

    if (ref == null || ref.isEmpty) {
      try {
        final tSnap = await FirebaseFirestore.instance
            .collection('tasks')
            .where('sub_categories_ref', isEqualTo: subDoc.reference)
            .limit(1)
            .get();
        if (tSnap.docs.isNotEmpty) {
          ref = tSnap.docs.first.data()['referenceoftask']?.toString();
        }
      } catch (_) {}
    }

    if (!mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddNewNcScreen(
          mainCategoryName: widget.parentCategoryName,
          mainCategoryRef: widget.mainCategoryRef,
          initialSubCategoryName: subCatName,
          initialSubCategoryRef: subDoc.reference,
          initialReference: (ref != null && ref.isNotEmpty) ? ref : null,
          turbineId: widget.turbineId,
          turbineModelRef: widget.turbineModelRef,
          draftId: widget.draftId,
        ),
      ),
    );
    _recalculateStatsFromLocal();
  }

  void _openCustomSubCatModal() {
    Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddNewNcScreen(
          mainCategoryName: widget.parentCategoryName,
          mainCategoryRef: widget.mainCategoryRef,
          turbineId: widget.turbineId,
          turbineModelRef: widget.turbineModelRef,
          draftId: widget.draftId,
        ),
      ),
    ).then((saved) {
      if (saved == true) {
        _recalculateStatsFromLocal();
      }
    });
  }
}
