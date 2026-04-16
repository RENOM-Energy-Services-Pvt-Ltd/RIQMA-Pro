import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/audit_manager.dart';
import '../widgets/audit_card_widget.dart';
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
      if (mounted) setState(() => _isLoading = false);
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
      setState(() {
        _subCategories
          ..clear()
          ..addAll(snapshot.docs);
        _isLoading = false;
      });
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

    setState(() {
      _subCategories
        ..clear()
        ..addAll(sorted);
      _isLoading = false; // Mark as done after first merge
    });
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
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _subCategories.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.list_alt_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('No sub-categories found', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                      const SizedBox(height: 8),
                      const Text('Check "target_models" for this model', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
          : GridView.builder(
              padding: const EdgeInsets.all(16.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.3, // Wider cards
              ),
              itemCount: _subCategories.length,
              itemBuilder: (context, index) {
                final doc = _subCategories[index];
                final data = doc.data() as Map<String, dynamic>;
                final categoryName = (data['name'] as String?) ?? 'Unknown';

                return FutureBuilder<Map<String, int>>(
                  future: _calculateSubCategoryProgress(doc.reference),
                  builder: (context, snapshot) {
                    final stats = snapshot.data ?? {'total': 0, 'ok': 0, 'notOk': 0, 'na': 0};
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
                        ).then((_) => setState(() {}));
                      },
                    );
                  },
                );
              },
            ),
    );
  }


  Future<Map<String, int>> _calculateSubCategoryProgress(DocumentReference subCategoryRef) async {
    // Initialize with draftId to ensure correct storage context
    if (widget.draftId != null) {
      await AuditManager.instance.init(draftId: widget.draftId);
    }
    final allAnswers = AuditManager.instance.getAllAnswers();

    final tasksSnapshot = await FirebaseFirestore.instance
        .collection('tasks')
        .where('sub_categories_ref', isEqualTo: subCategoryRef)
        .get();

    final total = tasksSnapshot.docs.length;
    var okCount = 0;
    var notOkCount = 0;
    var naCount = 0;

    for (var taskDoc in tasksSnapshot.docs) {
      final taskId = taskDoc.id;
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

    return {'total': total, 'ok': okCount, 'notOk': notOkCount, 'na': naCount};
  }
}
