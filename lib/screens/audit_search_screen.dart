import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/audit_manager.dart';
import 'audit_task_screen.dart';

/// A searchable task item with all metadata needed for display and navigation.
class _SearchableTask {
  final String taskId;
  final String title;
  final String description;
  final String mainCategoryName;
  final DocumentReference mainCategoryRef;
  final String subCategoryName;
  final DocumentReference subCategoryRef;
  final String referenceOfTask;
  String observation = ''; // local observation from AuditManager
  double score = 0; // relevance score for sorting

  _SearchableTask({
    required this.taskId,
    required this.title,
    required this.description,
    required this.mainCategoryName,
    required this.mainCategoryRef,
    required this.subCategoryName,
    required this.subCategoryRef,
    required this.referenceOfTask,
  });
}

class AuditSearchScreen extends StatefulWidget {
  final DocumentReference turbineModelRef;
  final String? draftId;

  const AuditSearchScreen({
    required this.turbineModelRef, super.key,
    this.draftId,
  });

  @override
  State<AuditSearchScreen> createState() => _AuditSearchScreenState();
}

class _AuditSearchScreenState extends State<AuditSearchScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounceTimer;

  List<_SearchableTask> _allTasks = [];
  List<_SearchableTask> _filteredTasks = [];
  bool _isLoading = true;
  bool _searchInObservations = false;
  String _query = '';

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);

    _loadAllTasks();

    // Auto-focus after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _debounceTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  // ─────────────────── DATA LOADING ───────────────────

  Future<void> _loadAllTasks() async {
    try {
      // Initialize AuditManager with correct draft context
      if (widget.draftId != null) {
        await AuditManager.instance.init(draftId: widget.draftId);
      }

      final tasks = <_SearchableTask>[];

      // 1. Get all main categories for this turbine model
      // 1. Get all relevant main categories
      final mainCatsSnapshot = await FirebaseFirestore.instance
          .collection('main_categories')
          .where('target_models', arrayContains: widget.turbineModelRef.id)
          .get();
      
      final allModelsSnapshot = await FirebaseFirestore.instance
          .collection('main_categories')
          .where('is_all_models', isEqualTo: true)
          .get();

      final combinedDocs = [...mainCatsSnapshot.docs, ...allModelsSnapshot.docs];
      // remove duplicates if any (though unlikely based on schema)
      final uniqueDocs = {for (var doc in combinedDocs) doc.id: doc}.values.toList();

      final allAnswers = AuditManager.instance.getAllAnswers();

      for (var mainCatDoc in uniqueDocs) {
        final mainCatData = mainCatDoc.data();
        final mainCatName = (mainCatData['name'] as String?) ?? 'Unknown';

        // 2. Get sub categories
        final subCatsSnapshot = await FirebaseFirestore.instance
            .collection('sub_categories')
            .where('main_categories_ref', isEqualTo: mainCatDoc.reference)
            .get();

        for (var subCatDoc in subCatsSnapshot.docs) {
          final subCatData = subCatDoc.data();
          final isAllModels = subCatData['is_all_models'] == true;
          final targetModels = subCatData['target_models'] as List<dynamic>? ?? [];
          final isApplicable = isAllModels || targetModels.contains(widget.turbineModelRef.id);
          if (!isApplicable) continue;

          final subCatName = (subCatData['name'] as String?) ?? 'Unknown';

          // 3. Get tasks
          final tasksSnapshot = await FirebaseFirestore.instance
              .collection('tasks')
              .where('sub_categories_ref', isEqualTo: subCatDoc.reference)
              .get();

          for (var taskDoc in tasksSnapshot.docs) {
            final data = taskDoc.data();
            final taskId = taskDoc.id;
            
            final task = _SearchableTask(
              taskId: taskId,
              title: (data['title'] as String?) ?? '',
              description: (data['description'] as String?) ?? '',
              mainCategoryName: mainCatName,
              mainCategoryRef: mainCatDoc.reference,
              subCategoryName: subCatName,
              subCategoryRef: subCatDoc.reference,
              referenceOfTask: data['referenceoftask']?.toString() ?? '',
            );

            // Attach local observation if exists
            if (allAnswers.containsKey(taskId)) {
              final answerData = allAnswers[taskId] as Map<String, dynamic>?;
              task.observation = answerData?['observation']?.toString() ?? '';
            }

            tasks.add(task);
          }
        }
      }

      if (mounted) {
        setState(() {
          _allTasks = tasks;
          _isLoading = false;
        });
        unawaited(_animController.forward());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        debugPrint('Error loading tasks for search: $e');
      }
    }
  }

  // ─────────────────── SEARCH LOGIC ───────────────────

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s_\-\(\)\+\/\.:]+'), '');

  void _performSearch(String query) {
    final trimmed = query.trim().toLowerCase();
    final queryNorm = _normalize(query);
    if (trimmed.isEmpty || queryNorm.isEmpty) {
      setState(() {
        _query = '';
        _filteredTasks = [];
      });
      return;
    }

    setState(() {
      _query = trimmed;
    });

    final queryWords =
        trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    final scored = <_SearchableTask>[];

    for (var task in _allTasks) {
      double score = 0;
      final titleLower = task.title.toLowerCase();
      final titleNorm = _normalize(task.title);
      final observationLower = task.observation.toLowerCase();
      final obsNorm = _normalize(task.observation);
      final descLower = task.description.toLowerCase();
      final descNorm = _normalize(task.description);
      final mainCatLower = task.mainCategoryName.toLowerCase();
      final mainCatNorm = _normalize(task.mainCategoryName);
      final subCatLower = task.subCategoryName.toLowerCase();
      final subCatNorm = _normalize(task.subCategoryName);
      final refLower = task.referenceOfTask.toLowerCase();
      final refNorm = _normalize(task.referenceOfTask);

      // 1. Normalized exact / start / contains match (Space & Punctuation Insensitive)
      if (titleNorm == queryNorm) {
        score += 500;
      } else if (titleNorm.startsWith(queryNorm)) {
        score += 250;
      } else if (titleNorm.contains(queryNorm)) {
        score += 150;
      }

      // 2. Category & Reference match (e.g. "tower wtg" or "towerwtg")
      if (subCatNorm.contains(queryNorm)) {
        score += 120;
      }
      if (mainCatNorm.contains(queryNorm)) {
        score += 100;
      }
      if (refNorm.contains(queryNorm)) {
        score += 120;
      }

      // 3. Observation match
      if (_searchInObservations) {
        if (obsNorm.contains(queryNorm)) {
          score += 150;
          if (obsNorm == queryNorm) score += 100;
        }
      }

      // 4. Per-word matching (tokenized for multiple words)
      var wordsFoundInTitle = 0;
      for (var word in queryWords) {
        final wordNorm = _normalize(word);
        if (titleLower.contains(word) || (wordNorm.isNotEmpty && titleNorm.contains(wordNorm))) {
          wordsFoundInTitle++;
          score += 40;
        }
        if (_searchInObservations && (observationLower.contains(word) || (wordNorm.isNotEmpty && obsNorm.contains(wordNorm)))) {
          score += 20;
        }
        if (subCatLower.contains(word) || (wordNorm.isNotEmpty && subCatNorm.contains(wordNorm))) {
          score += 20;
        }
        if (mainCatLower.contains(word) || (wordNorm.isNotEmpty && mainCatNorm.contains(wordNorm))) {
          score += 15;
        }
        if (descLower.contains(word) || (wordNorm.isNotEmpty && descNorm.contains(wordNorm))) {
          score += 10;
        }
        if (refLower.contains(word) || (wordNorm.isNotEmpty && refNorm.contains(wordNorm))) {
          score += 25;
        }
      }

      // Bonus if all query words found in title
      if (wordsFoundInTitle == queryWords.length && queryWords.length > 1) {
        score += 100;
      }

      if (score > 0) {
        task.score = score;
        scored.add(task);
      }
    }

    // Sort by score descending
    scored.sort((a, b) => b.score.compareTo(a.score));

    setState(() {
      _filteredTasks = scored;
    });
  }

  // ─────────────────── NAVIGATION ───────────────────

  void _navigateToTask(_SearchableTask task) {
    // Dismiss keyboard immediately before navigation
    _focusNode.unfocus();
    FocusScope.of(context).unfocus();

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => AuditTaskScreen(
          subCategoryName: task.subCategoryName,
          subCategoryRef: task.subCategoryRef,
          mainCategoryName: task.mainCategoryName,
          mainCategoryRef: task.mainCategoryRef,
          initialTaskId: task.taskId,
          draftId: widget.draftId,
          turbineId: widget.turbineModelRef.id,
        ),
      ),
    ).then((_) {
      // Refresh audit status on return
      if (mounted) setState(() {});
    });
  }

  // ─────────────────── HELPERS ───────────────────

  /// Get audit status for a task from AuditManager
  String _getTaskStatus(String taskId) {
    final allAnswers = AuditManager.instance.getAllAnswers();
    if (allAnswers.containsKey(taskId)) {
      final answerData = allAnswers[taskId] as Map<String, dynamic>?;
      final status = answerData?['status'];
      if (status == 'OK') return 'OK';
      if (status == 'Not OK') return 'Not OK';
    }
    return 'Pending';
  }

  bool _isTaskCorrected(String taskId) {
    final allAnswers = AuditManager.instance.getAllAnswers();
    final answerData = allAnswers[taskId] as Map<String, dynamic>?;
    return answerData?['is_corrected'] == true;
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'OK':
        return const Color(0xFF388E3C);
      case 'Not OK':
        return const Color(0xFFD32F2F);
      default:
        return const Color(0xFFF57C00);
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'OK':
        return Icons.check_circle;
      case 'Not OK':
        return Icons.cancel;
      default:
        return Icons.schedule;
    }
  }

  /// Highlights matching portions in the text
  List<TextSpan> _highlightMatches(String text, String query) {
    if (query.isEmpty) {
      return [TextSpan(text: text)];
    }

    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    var start = 0;

    while (start < text.length) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }

      // Text before match
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }

      // Matched portion
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: const TextStyle(
          backgroundColor: Color(0x3300E5FF),
          color: Color(0xFF0D47A1),
          fontWeight: FontWeight.bold,
        ),
      ));

      start = index + query.length;
    }

    return spans;
  }

  // ─────────────────── BUILD ───────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          _buildSearchHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        bottom: 20,
        left: 16,
        right: 16,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF00E5FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Back + Title
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const Text(
                'Search Checkpoints',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              if (_allTasks.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_allTasks.length} items',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Search Bar
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _focusNode,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(fontSize: 16, color: Colors.black87),
                    decoration: InputDecoration(
                      hintText: 'Search by checkpoint, category...',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                      prefixIcon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _isLoading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF00897B),
                                  ),
                                ),
                              )
                            : const Icon(Icons.search_rounded,
                                color: Color(0xFF1A237E)),
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded,
                                  color: Colors.grey),
                              onPressed: () {
                                _searchController.clear();
                                _performSearch('');
                                _focusNode.requestFocus();
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: Colors.grey.withValues(alpha: 0.2),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _searchInObservations = !_searchInObservations;
                    });
                    _performSearch(_searchController.text);
                  },
                  icon: Icon(
                    _searchInObservations ? Icons.check_circle : Icons.notes,
                    size: 18,
                    color: _searchInObservations
                        ? const Color(0xFF00897B)
                        : Colors.grey.shade600,
                  ),
                  label: Text(
                    'Notes',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _searchInObservations
                          ? const Color(0xFF00897B)
                          : Colors.grey.shade600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildLoadingShimmer();
    }

    if (_query.isEmpty) {
      return _buildEmptyState();
    }

    if (_filteredTasks.isEmpty) {
      return _buildNoResults();
    }

    return _buildResultsList();
  }

  Widget _buildLoadingShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 90,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 200,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: 140,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 100,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1A237E).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.manage_search_rounded,
                size: 56,
                color: Color(0xFF1A237E),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Search Checkpoints',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A237E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Type to find any checkpoint across\nall categories instantly',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off_rounded,
              size: 48,
              color: Colors.orange,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Results Found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different keyword or\ncheck the spelling',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Results count bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A237E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_filteredTasks.length} result${_filteredTasks.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'Sorted by relevance',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        // Results list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: _filteredTasks.length,
            itemBuilder: (context, index) {
              final task = _filteredTasks[index];
              return _buildResultCard(task, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResultCard(_SearchableTask task, int index) {
    final status = _getTaskStatus(task.taskId);
    final isCorrected = _isTaskCorrected(task.taskId);
    final statusColor = _getStatusColor(status);
    final statusIcon = _getStatusIcon(status);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 200 + (index * 50).clamp(0, 300)),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.grey.shade200,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _navigateToTask(task),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Left: Status indicator
                  Container(
                    width: 4,
                    height: 56,
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Middle: Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title with highlights
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                            children: _highlightMatches(task.title, _query),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        // Breadcrumb
                        Row(
                          children: [
                            Icon(Icons.folder_outlined,
                                size: 13, color: Colors.blueGrey.shade400),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '${task.mainCategoryName} › ${task.subCategoryName}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blueGrey.shade600,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (task.observation.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF8E1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.notes, size: 14, color: Colors.amber.shade800),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.amber.shade900,
                                        fontStyle: FontStyle.italic,
                                      ),
                                      children: _highlightMatches(task.observation, _query),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (task.referenceOfTask.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(Icons.bookmark_border,
                                  size: 13, color: Colors.grey.shade400),
                              const SizedBox(width: 4),
                              Text(
                                'Ref: ${task.referenceOfTask}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Right: Status badge
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, size: 12, color: statusColor),
                            const SizedBox(width: 4),
                            Text(
                              status,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isCorrected) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.green.withValues(alpha: 0.4),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome,
                                  size: 10, color: Colors.green),
                              SizedBox(width: 3),
                              Text(
                                'Corrected',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Icon(Icons.arrow_forward_ios,
                          size: 12, color: Colors.grey.shade400),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
