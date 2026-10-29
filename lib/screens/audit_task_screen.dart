import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/app_settings_provider.dart';
import '../services/audit_manager.dart';
import 'audit_search_screen.dart';

Future<ImageSource?> _selectPhotoSource(BuildContext ctx) async {
  final appSettings = Provider.of<AppSettingsProvider>(ctx, listen: false);
  if (!appSettings.allowGalleryImport) {
    return ImageSource.camera;
  }

  return showModalBottomSheet<ImageSource>(
    context: ctx,
    backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Text(
                'Select Photo Source',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(sheetCtx).colorScheme.onSurface,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF1A237E)),
              title: const Text('Take Photo (Camera)', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(sheetCtx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFF00897B)),
              title: const Text('Import from Gallery', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(sheetCtx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Snappy page scroll physics that settles quickly with ZERO pendulum bounce.
/// - Normal swipe: precisely 1 page switch.
/// - Fast flick (>2800 px/s): 2 pages switch.
/// - Ultra-fast fling (>5000 px/s): 3 pages switch.
class FastPageScrollPhysics extends PageScrollPhysics {
  const FastPageScrollPhysics({super.parent});

  @override
  FastPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return FastPageScrollPhysics(parent: buildParent(ancestor));
  }

  // Critically overdamped spring: damping ratio = 23 / (2 * sqrt(0.5 * 220)) = 1.096 (>= 1.0)
  // This physically guarantees ZERO overshoot, ZERO oscillation, and ZERO pendulum bounce.
  @override
  SpringDescription get spring => const SpringDescription(
    mass: 0.5,
    stiffness: 220.0,
    damping: 23.0,
  );

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    // If out of range (overscroll at edge), let parent handle bounce
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }

    final double pageWidth = position.viewportDimension;
    if (pageWidth <= 0) return super.createBallisticSimulation(position, velocity);

    final Tolerance tolerance = toleranceFor(position);
    final double currentPage = position.pixels / pageWidth;
    final double absVelocity = velocity.abs();

    double targetPage;

    if (absVelocity < tolerance.velocity || absVelocity < 200.0) {
      // Very slow / drag release: snap to nearest page (>50% goes to next, <50% snaps back)
      targetPage = currentPage.roundToDouble();
    } else {
      // Swipe with velocity:
      // Normal swipe -> exactly 1 page
      // Fast swipe (> 2800 px/s) -> 2 pages
      // Ultra-fast swipe (> 5000 px/s) -> 3 pages
      int pageDelta = 1;
      if (absVelocity > 5000.0) {
        pageDelta = 3;
      } else if (absVelocity > 2800.0) {
        pageDelta = 2;
      } else {
        pageDelta = 1;
      }

      if (velocity > 0) {
        // Forward swipe
        targetPage = (currentPage.floor() + pageDelta).toDouble();
      } else {
        // Backward swipe
        targetPage = (currentPage.ceil() - pageDelta).toDouble();
      }
    }

    // Clamp within valid min and max page indices
    final double minPage = (position.minScrollExtent / pageWidth).roundToDouble();
    final double maxPage = (position.maxScrollExtent / pageWidth).roundToDouble();
    targetPage = targetPage.clamp(minPage, maxPage);

    final double targetPixels = targetPage * pageWidth;

    if ((targetPixels - position.pixels).abs() < 0.5) {
      return null;
    }

    return ScrollSpringSimulation(
      spring,
      position.pixels,
      targetPixels,
      velocity,
      tolerance: tolerance,
    );
  }
}

class AuditTaskScreen extends StatefulWidget {
  final String subCategoryName;
  final DocumentReference subCategoryRef;
  final String mainCategoryName;
  final DocumentReference mainCategoryRef;
  final String? initialTaskId;
  final String? turbineId;
  final String? draftId;

  const AuditTaskScreen({
    required this.subCategoryName, required this.subCategoryRef, required this.mainCategoryName, required this.mainCategoryRef, super.key,
    this.initialTaskId,
    this.turbineId,
    this.draftId,
  });

  @override
  State<AuditTaskScreen> createState() => _AuditTaskScreenState();
}

class _AuditTaskScreenState extends State<AuditTaskScreen> {
  final PageController _pageController = PageController();
  final ValueNotifier<bool> _isPageScrolling = ValueNotifier<bool>(false);
  int _currentPage = 0;
  int _totalDocs = 0;
  bool _hasJumpedToInitialTask = false;

  // Store answers by task ID
  // Structure: { 'taskId': { 'status': 'OK'/'Not OK', 'observation': '...', 'remarks': '...', 'photos': ['path1', 'path2'] } }
  final Map<String, Map<String, dynamic>> auditData = {};

  // Cache for reference names: { 'referenceId': 'Reference Name' }
  final Map<String, String> _referenceNames = {};
  
  // Master data for Task 7
  List<String> _rootCauses = [];

  @override
  void initState() {
    super.initState();
    _loadSavedData();
    _loadCachedReferences();
    _fetchReferences();
    _fetchRootCauses();
  }

  Future<void> _loadCachedReferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('cached_reference_names_map');
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final decoded = jsonDecode(cachedJson);
        if (decoded is Map && mounted) {
          setState(() {
            decoded.forEach((key, value) {
              _referenceNames[key.toString()] = value.toString();
            });
          });
          _propagateResolvedReferences();
        }
      }
    } catch (e) {
      debugPrint('Error loading cached references: $e');
    }
  }

  Future<void> _fetchRootCauses() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('audit_configs').doc('root_causes').get();
      if (doc.exists && mounted) {
        final data = doc.data();
        if (data != null && data['values'] is List) {
          setState(() {
            _rootCauses = List<String>.from(data['values'] as List);
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching root causes: $e');
    }
  }

  Future<void> _fetchReferences() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('references').get();
      if (mounted) {
        setState(() {
          for (var doc in snapshot.docs) {
            final data = doc.data();
            _referenceNames[doc.id] = data['name']?.toString() ?? 'Unknown Reference';
          }
        });

        // Persist to local cache for offline/weak network resilience
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('cached_reference_names_map', jsonEncode(_referenceNames));
        } catch (_) {}

        // Retroactively heal/update any answers in current audit that were missing reference_name
        _propagateResolvedReferences();
      }
    } catch (e) {
      debugPrint('Error fetching references: $e');
    }
  }

  void _propagateResolvedReferences() {
    if (_referenceNames.isEmpty || _tasks.isEmpty) return;
    for (final taskDoc in _tasks) {
      final taskId = taskDoc.id;
      // CRITICAL GUARD: Only propagate references for tasks the user has actually answered!
      // Never create empty dummy answers for unanswered tasks.
      if (!auditData.containsKey(taskId)) continue;
      final currentAnswer = auditData[taskId];
      if (currentAnswer == null || currentAnswer['status'] == null) continue;

      final taskData = taskDoc.data() as Map<String, dynamic>;
      if (taskData.containsKey('reference_ref') && taskData['reference_ref'] is DocumentReference) {
        final refDoc = taskData['reference_ref'] as DocumentReference;
        final refId = refDoc.id;
        final refPath = refDoc.path;
        final resolvedName = _referenceNames[refId];
        if (resolvedName != null &&
            resolvedName.isNotEmpty &&
            resolvedName != 'Loading...' &&
            resolvedName != 'N/A') {
          final existing = currentAnswer['reference_name']?.toString() ?? '';
          if (existing.isEmpty || existing == 'Loading...' || existing == 'N/A') {
            _updateAnswer(taskId, 'reference_name', resolvedName, shouldSetState: false);
            _updateAnswer(taskId, 'reference_id', refId, shouldSetState: false);
            _updateAnswer(taskId, 'reference_ref', refPath, shouldSetState: false);
          }
        }
      }
    }
  }

  Future<void> _loadSavedData() async {
    // initialize with correct draftId to ensure we load the right file
    await AuditManager.instance.init(draftId: widget.draftId);
    if (!mounted) return;
    setState(() {
      AuditManager.instance.getAllAnswers().forEach((key, value) {
        if (value is Map) {
          final map = Map<String, dynamic>.from(value);
          if (map['is_corrected'] == true && map['status'] != 'Not OK') {
            map['status'] = 'Not OK';
            AuditManager.instance.saveAnswer(key, map);
          }
          auditData[key] = map;
        }
      });
    });
  }

  @override
  void dispose() {
    AuditManager.instance.flush();
    _pageController.dispose();
    _isPageScrolling.dispose();
    super.dispose();
  }

  void _updateAnswer(String taskId, String key, dynamic value, {bool shouldSetState = true}) {
    if (shouldSetState) {
      setState(() {
        if (!auditData.containsKey(taskId)) {
          auditData[taskId] = {};
        }
        auditData[taskId]![key] = value;
      });
    } else {
      if (!auditData.containsKey(taskId)) {
        auditData[taskId] = {};
      }
      auditData[taskId]![key] = value;
    }
    
    // Save to local storage immediately
    AuditManager.instance.saveAnswer(taskId, auditData[taskId]!);
  }

  // Helper to ensure category details are present
  void _ensureCategoryDetails(String taskId) {
    if (auditData[taskId] == null) return;
    
    var changed = false;
    if (auditData[taskId]!['main_category_id'] != widget.mainCategoryRef.id) {
      auditData[taskId]!['main_category_id'] = widget.mainCategoryRef.id;
      changed = true;
    }
    if (auditData[taskId]!['main_category_name'] != widget.mainCategoryName) {
      auditData[taskId]!['main_category_name'] = widget.mainCategoryName;
      changed = true;
    }
    if (auditData[taskId]!['sub_category_id'] != widget.subCategoryRef.id) {
      auditData[taskId]!['sub_category_id'] = widget.subCategoryRef.id;
      changed = true;
    }
    if (auditData[taskId]!['sub_category_name'] != widget.subCategoryName) {
      auditData[taskId]!['sub_category_name'] = widget.subCategoryName;
      changed = true;
    }
    if (widget.turbineId != null && auditData[taskId]!['turbine_id'] != widget.turbineId) {
      auditData[taskId]!['turbine_id'] = widget.turbineId!;
      changed = true;
    }
    
    if (changed) {
      // Background save already handled by _updateAnswer if it was called,
      // but if we changed things directly in auditData, we should trigger a save.
      AuditManager.instance.saveAnswer(taskId, auditData[taskId]!);
    }
  }

  Future<void> _capturePhoto(String taskId) async {
    try {
      final source = await _selectPhotoSource(context);
      if (source == null) return;

      final picker = ImagePicker();
      final image = await picker.pickImage(source: source);

      if (image != null) {
        String finalPath;

        if (kIsWeb) {
          // Web: Skip compression and saving, use path directly (blob url)
          finalPath = image.path;
        } else {
          // Mobile: Compress and save
          final appDir = await getApplicationDocumentsDirectory();
          final fileName = '${taskId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final targetPath = p.join(appDir.path, fileName);

          String? savedPath;
          try {
            final compressedFile = await FlutterImageCompress.compressAndGetFile(
              image.path,
              targetPath,
              quality: 85,
            );
            if (compressedFile != null && await File(compressedFile.path).exists()) {
              savedPath = compressedFile.path;
            }
          } catch (compressErr) {
            debugPrint('⚠️ Image compression error: $compressErr, falling back to original copy');
          }

          // Bulletproof Fallback: If compression returned null or failed, copy original file directly!
          if (savedPath == null) {
            try {
              final originalFile = File(image.path);
              if (await originalFile.exists()) {
                final copiedFile = await originalFile.copy(targetPath);
                savedPath = copiedFile.path;
              } else {
                savedPath = image.path;
              }
            } catch (copyErr) {
              debugPrint('⚠️ Error copying original image: $copyErr');
              savedPath = image.path;
            }
          }

          finalPath = savedPath;
        }

        // Update auditData
        if (!auditData.containsKey(taskId)) {
          auditData[taskId] = {};
        }
        final currentPhotos = List<String>.from((auditData[taskId]!['photos'] as List<dynamic>?) ?? [])..add(finalPath);
        _updateAnswer(taskId, 'photos', currentPhotos);
      }
    } catch (e) {
      debugPrint('❌ Error in _capturePhoto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to attach photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removePhoto(String taskId, String photoPath) async {
    if (!auditData.containsKey(taskId)) return;
    final currentPhotos = List<String>.from((auditData[taskId]!['photos'] as List<dynamic>?) ?? [])..remove(photoPath);
    _updateAnswer(taskId, 'photos', currentPhotos);

    if (!kIsWeb) {
      try {
        final file = File(photoPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('Error deleting photo file: $e');
      }
    }
  }

  List<QueryDocumentSnapshot> _tasks = [];

  bool _validateTask() {
    if (_tasks.isEmpty) return true;
    
    final appSettings = Provider.of<AppSettingsProvider>(context, listen: false);
    final currentTaskId = _tasks[_currentPage].id;
    final currentData = auditData[currentTaskId];
    
    final status = currentData?['status'];
    final observation = currentData?['observation'] as String?;
    
    // Check Mandatory Observation (regardless of status)
    if (appSettings.mandatoryObservationText && (observation == null || observation.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Observation is mandatory'), backgroundColor: Colors.red),
      );
      return false;
    }

    if (status == 'Not OK') {
      final photos = currentData?['photos'] as List<dynamic>?;
      if (photos == null || photos.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please attach a photo for "Not OK" status'),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      }

      if (currentData?['sub_status'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a severity level (Aobs, MCF, CF)'),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      }

      // Strict Navigation Check
      if (appSettings.restrictNavWithoutDetails) {
        if (observation == null || observation.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Observation is required for "Not OK" status'),
              backgroundColor: Colors.red,
            ),
          );
          return false;
        }
      }
    }
    return true;
  }

  void _nextPage() {
    if (_isPageScrolling.value) return;
    if (!_validateTask()) return;

    if (_currentPage < _totalDocs - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
      );
    } else {
      AuditManager.instance.flush();
      Navigator.of(context).pop();
    }
  }

  void _saveAndReturn() {
    if (!_validateTask()) return;

    AuditManager.instance.flush();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Progress Saved'),
        duration: Duration(seconds: 1),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.of(context).pop();
  }

  void _previousPage() {
    if (_isPageScrolling.value) return;
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA), // Soft grey-blue background
        body: Column(
        children: [
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 8,
              bottom: 12,
              left: 16,
              right: 16,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A237E), Color(0xFF00E5FF)], // Deep Blue to Electric Teal
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.mainCategoryName,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontFamily: 'Outfit',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.subCategoryName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Content
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('tasks')
                  .where('sub_categories_ref', isEqualTo: widget.subCategoryRef)
                  .orderBy('sort_order', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final tasks = snapshot.data!.docs;
                _totalDocs = tasks.length;
                
                // Update local tasks list for validation
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    if (_tasks.length != tasks.length) {
                      setState(() {
                        _tasks = tasks;
                      });
                    }
                    
                    // Handle deep linking to specific task (only once on initial load)
                    if (widget.initialTaskId != null && !_hasJumpedToInitialTask && _pageController.hasClients) {
                      final index = tasks.indexWhere((doc) => doc.id == widget.initialTaskId);
                      if (index != -1) {
                        _hasJumpedToInitialTask = true;
                        _currentPage = index;
                        _pageController.jumpToPage(index);
                      }
                    }
                  }
                });

                if (tasks.isEmpty) {
                  return const Center(child: Text('No tasks found for this category.'));
                }

                return NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.axis == Axis.horizontal) {
                      if (notification is ScrollStartNotification) {
                        _isPageScrolling.value = true;
                      } else if (notification is ScrollEndNotification) {
                        _isPageScrolling.value = false;
                      }
                    }
                    return false;
                  },
                  child: PageView.builder(
                    controller: _pageController,
                    physics: const FastPageScrollPhysics(),
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final taskDoc = tasks[index];
                      final taskData = taskDoc.data() as Map<String, dynamic>;
                      final taskId = taskDoc.id;

                      // Resolve Reference Name safely without ever falling back to placeholder strings
                      String? refId;
                      if (taskData.containsKey('reference_ref') && taskData['reference_ref'] is DocumentReference) {
                        refId = (taskData['reference_ref'] as DocumentReference).id;
                      }

                      var referenceName = '';
                      if (refId != null && _referenceNames.containsKey(refId)) {
                        referenceName = _referenceNames[refId]!;
                      } else {
                        final nativeRef = taskData['referenceoftask']?.toString().trim() ?? '';
                        if (nativeRef.isNotEmpty && nativeRef != 'N/A' && nativeRef != 'Loading...') {
                          referenceName = nativeRef;
                        } else {
                          referenceName = '';
                        }
                      }

                      return TaskPageItem(
                        key: ValueKey(taskId),
                        taskData: taskData,
                        referenceName: referenceName.isNotEmpty ? referenceName : 'N/A', // This is already prioritized in the parent via _referenceNames
                        rootCauses: _rootCauses,
                        initialAnswer: auditData[taskId] ?? {},
                        onAnswerChanged: (key, value, {bool shouldSetState = true}) {
                          _updateAnswer(taskId, key, value, shouldSetState: shouldSetState);
                          // Ensure category details and reference name are saved
                          _ensureCategoryDetails(taskId);
                          if (referenceName.isNotEmpty &&
                              referenceName != 'Loading...' &&
                              referenceName != 'N/A') {
                            if (auditData[taskId]?['reference_name'] != referenceName) {
                              _updateAnswer(taskId, 'reference_name', referenceName, shouldSetState: false);
                            }
                          }
                          if (refId != null && auditData[taskId]?['reference_id'] != refId) {
                            _updateAnswer(taskId, 'reference_id', refId, shouldSetState: false);
                            final refDoc = taskData['reference_ref'];
                            final refPath = (refDoc is DocumentReference) ? refDoc.path : refDoc?.toString() ?? refId;
                            _updateAnswer(taskId, 'reference_ref', refPath, shouldSetState: false);
                          }
                        },
                        onCapturePhoto: () => _capturePhoto(taskId),
                        onRemovePhoto: (path) => _removePhoto(taskId, path),
                        turbineModelRef: widget.mainCategoryRef, // Using mainCategoryRef as turbineModelRef based on context in AuditTaskScreen
                        draftId: widget.draftId,
                        isPageScrolling: _isPageScrolling,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).brightness == Brightness.dark 
                  ? Colors.black.withValues(alpha: 0.3) 
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (_currentPage > 0)
              TextButton.icon(
                onPressed: _previousPage,
                icon: const Icon(Icons.arrow_back, color: Colors.grey),
                label: const Text('Previous', style: TextStyle(color: Colors.grey)),
              )
            else
              const SizedBox(width: 80),

            // Checkpoint Counter (e.g. 01/10)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1A237E).withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF1A237E).withValues(alpha: 0.15),
                ),
              ),
              child: Text(
                '${_totalDocs > 0 ? (_currentPage + 1).toString().padLeft(2, '0') : '00'}/${_totalDocs.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A237E),
                  fontFamily: 'Outfit',
                  letterSpacing: 1.2,
                ),
              ),
            ),

            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00E5FF), Color(0xFF00897B)],
                ),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _currentPage == _totalDocs - 1 ? _saveAndReturn : _nextPage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: Text(
                  _currentPage == _totalDocs - 1 ? 'Save & Return' : 'Next',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}

class TaskPageItem extends StatefulWidget {
  final Map<String, dynamic> taskData;
  final String referenceName;
  final List<String> rootCauses;
  final Map<String, dynamic> initialAnswer;
  final void Function(String key, dynamic value, {bool shouldSetState}) onAnswerChanged;
  final VoidCallback onCapturePhoto;
  final void Function(String photoPath) onRemovePhoto;
  final DocumentReference turbineModelRef;
  final String? draftId;
  final ValueListenable<bool>? isPageScrolling;

  const TaskPageItem({
    required this.taskData,
    required this.referenceName,
    required this.rootCauses,
    required this.initialAnswer,
    required this.onAnswerChanged,
    required this.onCapturePhoto,
    required this.onRemovePhoto,
    required this.turbineModelRef,
    this.draftId,
    this.isPageScrolling,
    super.key,
  });

  @override
  State<TaskPageItem> createState() => _TaskPageItemState();
}

class _TaskPageItemState extends State<TaskPageItem> with AutomaticKeepAliveClientMixin {
  late TextEditingController _observationController;
  late TextEditingController _remarksController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _observationController = TextEditingController(text: widget.initialAnswer['observation'] as String?);
    _remarksController = TextEditingController(text: widget.initialAnswer['remarks'] as String?);
    
    // Ensure static data (question title) is saved
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialAnswer['question'] == null) {
        widget.onAnswerChanged('question', widget.taskData['title'] ?? 'Unknown Question');
      }
      // Ensure reference name is saved if missing
      if (widget.initialAnswer['reference_name'] == null) {
        widget.onAnswerChanged('reference_name', widget.referenceName);
      }
    });
  }

  @override
  void dispose() {
    _observationController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _confirmAndRemovePhoto(BuildContext context, String path) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Photo'),
        content: const Text('Are you sure you want to remove this photo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('REMOVE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (shouldRemove == true) {
      widget.onRemovePhoto(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    final status = widget.initialAnswer['status'];
    final photos = List<String>.from((widget.initialAnswer['photos'] as List<dynamic>?) ?? []);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Card A: Question Details
          _buildElectricCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Html(
                  data: (widget.taskData['title_html']?.toString().isNotEmpty == true) 
                      ? widget.taskData['title_html'] as String? 
                      : (widget.taskData['title'] as String? ?? 'No Title'),
                  style: {
                    'body': Style(
                      fontSize: FontSize(14.0),
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                      fontFamily: 'Outfit',
                      margin: Margins.zero,
                      padding: HtmlPaddings.zero,
                    ),
                  },
                ),
                const SizedBox(height: 12),
                Html(
                  data: (widget.taskData['description_html']?.toString().isNotEmpty == true) 
                      ? widget.taskData['description_html'] as String? 
                      : (widget.taskData['description'] as String? ?? ''),
                  style: {
                    'body': Style(
                      fontSize: FontSize(13.0),
                      color: Colors.grey.shade700,
                      fontFamily: 'Outfit',
                      margin: Margins.zero,
                      padding: HtmlPaddings.zero,
                      lineHeight: const LineHeight(1.5),
                    ),
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _buildElectricCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Status',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatusButton(
                        label: 'OK',
                        isSelected: status == 'OK',
                        color: const Color(0xFF388E3C), // Sharp vibrant green
                        icon: Icons.check_circle_outline,
                        onTap: () {
                          if (widget.initialAnswer['is_corrected'] == true) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('This task has an On-Site Correction and remains "Not OK".'),
                                duration: Duration(seconds: 2),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }
                          widget.onAnswerChanged('status', 'OK');
                          widget.onAnswerChanged('sub_status', null);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: _buildStatusButton(
                              label: 'NOT OK',
                              isSelected: status == 'Not OK',
                              color: const Color(0xFFD32F2F), // Sharp vibrant red
                              icon: Icons.cancel_outlined,
                              onTap: () => widget.onAnswerChanged('status', 'Not OK'),
                            ),
                          ),
                          if (widget.initialAnswer['is_corrected'] == true)
                            Positioned(
                              top: -6,
                              right: -6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green[600],
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.1),
                                      blurRadius: 2,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check, color: Colors.white, size: 8),
                                    SizedBox(width: 2),
                                    Text(
                                      'Corrected',
                                      style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatusButton(
                        label: 'NA',
                        isSelected: status == 'NA',
                        color: Colors.grey.shade600, // Sleek grey
                        icon: Icons.do_not_disturb_alt,
                        onTap: () {
                          if (widget.initialAnswer['is_corrected'] == true) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('This task has an On-Site Correction and remains "Not OK".'),
                                duration: Duration(seconds: 2),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }
                          widget.onAnswerChanged('status', 'NA');
                          widget.onAnswerChanged('sub_status', null);
                        },
                      ),
                    ),
                  ],
                ),
                if (status == 'Not OK') ...[
                  const SizedBox(height: 16),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatusButton(
                          label: 'Aobs',
                          isSelected: widget.initialAnswer['sub_status'] == 'Aobs',
                          color: Colors.amber.shade700,
                          icon: Icons.warning_amber_rounded,
                          onTap: () => widget.onAnswerChanged('sub_status', 'Aobs'),
                          compact: true,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildStatusButton(
                          label: 'MCF',
                          isSelected: widget.initialAnswer['sub_status'] == 'MCF',
                          color: Colors.blue.shade700,
                          icon: Icons.info_outline,
                          onTap: () => widget.onAnswerChanged('sub_status', 'MCF'),
                          compact: true,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildStatusButton(
                          label: 'CF',
                          isSelected: widget.initialAnswer['sub_status'] == 'CF',
                          color: Colors.red.shade700,
                          icon: Icons.error_outline,
                          onTap: () => widget.onAnswerChanged('sub_status', 'CF'),
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Card C: Photos
          _buildElectricCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Photos',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${photos.length} Attached',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...photos.map((path) => Padding(
                        padding: const EdgeInsets.only(right: 14.0, top: 6.0),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            GestureDetector(
                              onTap: () => _showFullImage(context, path),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(5),
                                  child: (kIsWeb || path.startsWith('http'))
                                      ? Image.network(
                                          path,
                                          width: 80,
                                          height: 80,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            width: 80,
                                            height: 80,
                                            color: Colors.grey.shade200,
                                            child: const Icon(Icons.broken_image, color: Colors.grey, size: 24),
                                          ),
                                        )
                                      : Image.file(
                                          File(path),
                                          width: 80,
                                          height: 80,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            width: 80,
                                            height: 80,
                                            color: Colors.grey.shade200,
                                            child: const Icon(Icons.broken_image, color: Colors.grey, size: 24),
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: -6,
                              right: -6,
                              child: GestureDetector(
                                onTap: () => _confirmAndRemovePhoto(context, path),
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade600,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.25),
                                        blurRadius: 3,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                      if (photos.length < 3)
                        Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: GestureDetector(
                            onTap: widget.onCapturePhoto,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F7FA),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.5), width: 1.5, style: BorderStyle.solid),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.add_a_photo_outlined, color: Color(0xFF00E5FF), size: 24),
                                  const SizedBox(height: 2),
                                  Text('Add Photo', style: TextStyle(fontSize: 9, color: Colors.grey[600], fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Card D: Notes
          _buildElectricCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Notes',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                ),
                const SizedBox(height: 12),
                _buildModernTextField(
                  controller: _observationController,
                  label: 'Observation',
                  isMandatory: Provider.of<AppSettingsProvider>(context).mandatoryObservationText || 
                              (Provider.of<AppSettingsProvider>(context).restrictNavWithoutDetails && 
                               widget.initialAnswer['status'] == 'Not OK'),
                  icon: Icons.visibility_outlined,
                  onChanged: (val) => widget.onAnswerChanged('observation', val, shouldSetState: false),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.manage_search_rounded, color: Color(0xFF1A237E), size: 18),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (context) => AuditSearchScreen(
                            turbineModelRef: widget.turbineModelRef,
                            draftId: widget.draftId,
                          ),
                        ),
                      );
                    },
                    tooltip: 'Search Checkpoints',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Deviation Corrected Button (Visible if Not OK or already corrected)
          if (status == 'Not OK' || widget.initialAnswer['is_corrected'] == true) ...[
             _buildElectricCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                   Row(
                    children: [
                      Icon(
                        widget.initialAnswer['is_corrected'] == true 
                            ? Icons.check_circle 
                            : Icons.build_circle, 
                        color: widget.initialAnswer['is_corrected'] == true 
                            ? Colors.green 
                            : Colors.orange,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.initialAnswer['is_corrected'] == true 
                              ? 'Deviation Corrected On-Spot' 
                              : 'Fix Deviation Now?',
                          style: TextStyle(
                            fontSize: 16, 
                            fontWeight: FontWeight.bold,
                            color: widget.initialAnswer['is_corrected'] == true 
                                ? Colors.green[800] 
                                : Colors.orange[900],
                          ),
                        ),
                      ),
                    ],
                   ),
                   if (widget.initialAnswer['is_corrected'] == true) ...[
                     const SizedBox(height: 12),
                     Text(
                       'Remark: ${widget.initialAnswer['closure_remark'] ?? "-"}',
                       style: TextStyle(color: Colors.grey[800]),
                     ),
                      const SizedBox(height: 8),
                      // View Proof Button
                       if (widget.initialAnswer['closure_photo'] != null)
                         OutlinedButton.icon(
                           onPressed: () => _showFullImage(context, widget.initialAnswer['closure_photo'] as String),
                           icon: const Icon(Icons.image),
                           label: const Text('View Proof'),
                         ),
                   ],
                   const SizedBox(height: 16),
                   ElevatedButton(
                     onPressed: _showCorrectionDialog,
                     style: ElevatedButton.styleFrom(
                       backgroundColor: widget.initialAnswer['is_corrected'] == true ? Colors.grey[200] : const Color(0xFF00E5FF),
                       foregroundColor: widget.initialAnswer['is_corrected'] == true ? Colors.black : Colors.white,
                       padding: const EdgeInsets.symmetric(vertical: 12),
                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                     ),
                     child: Text(widget.initialAnswer['is_corrected'] == true ? 'Edit Correction' : 'Record On-Spot Correction'),
                   ),
                ],
              ),
             ),
             const SizedBox(height: 20),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildElectricCard({required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: const Color(0xFF1A237E).withValues(alpha: isDark ? 0.05 : 0.02),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: child,
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required void Function(String) onChanged,
    bool isMandatory = false,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      maxLines: 3,
      style: const TextStyle(fontSize: 14, fontFamily: 'Outfit'),
      decoration: InputDecoration(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (isMandatory)
              const Text(' *', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ],
        ),
        labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        alignLabelWithHint: true,
        suffixIcon: suffixIcon,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(bottom: 40),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
        ),
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.black26 : const Color(0xFFF8FAFC),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  void _showFullImage(BuildContext context, String path) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4,
              child: (kIsWeb || path.startsWith('http'))
                  ? Image.network(
                      path,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Center(
                        child: Icon(Icons.broken_image, color: Colors.white, size: 48),
                      ),
                    )
                  : Image.file(
                      File(path),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Center(
                        child: Icon(Icons.broken_image, color: Colors.white, size: 48),
                      ),
                    ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 24),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusButton({
    required String label,
    required bool isSelected,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
    bool compact = false,
  }) {
    final button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: compact ? 8 : 12),
        decoration: BoxDecoration(
          color: isSelected ? color : Theme.of(context).cardColor,
          border: Border.all(
            color: isSelected ? color : Theme.of(context).dividerColor.withValues(alpha: 0.1), 
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected ? [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ] : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey[500],
              size: compact ? 18 : 24,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                fontSize: compact ? 11 : 13,
                fontFamily: 'Outfit',
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.isPageScrolling != null) {
      return ValueListenableBuilder<bool>(
        valueListenable: widget.isPageScrolling!,
        builder: (context, isScrolling, child) {
          return IgnorePointer(
            ignoring: isScrolling,
            child: child,
          );
        },
        child: button,
      );
    }

    return button;
  }

  /// Compresses the closure photo locally and returns the local file path.
  /// Uses the same compression quality (85) as main observation photos.
  Future<String?> _compressClosurePhotoLocally(XFile imageFile) async {
    try {
      if (kIsWeb) {
        // Web: Skip compression, return path directly (blob URL)
        return imageFile.path;
      }
      
      // Mobile: Compress and save locally
      final appDir = await getApplicationDocumentsDirectory();
      final taskId = (widget.taskData['id'] as String?) ?? 'task';
      final fileName = '${taskId}_closure_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final targetPath = p.join(appDir.path, fileName);
      
      try {
        final compressedFile = await FlutterImageCompress.compressAndGetFile(
          imageFile.path,
          targetPath,
          quality: 85, // Match main observation photo quality
        );
        if (compressedFile != null && await File(compressedFile.path).exists()) {
          return compressedFile.path;
        }
      } catch (compressErr) {
        debugPrint('⚠️ Closure image compression failed: $compressErr, falling back to copy');
      }

      // Fallback: Copy original file directly
      try {
        final originalFile = File(imageFile.path);
        if (await originalFile.exists()) {
          final copied = await originalFile.copy(targetPath);
          return copied.path;
        }
      } catch (copyErr) {
        debugPrint('⚠️ Error copying original closure image: $copyErr');
      }
      
      return imageFile.path;
    } catch (e) {
      debugPrint('Error compressing closure photo: $e');
      return imageFile.path;
    }
  }

  void _showCorrectionDialog() {
    final remarkController = TextEditingController(text: widget.initialAnswer['closure_remark'] as String?);
    var currentPhotoUrl = widget.initialAnswer['closure_photo'] as String?;
    var selectedRootCause = widget.initialAnswer['root_cause'] as String?;
    // Local path for preview before upload if needed, though we upload on save
    XFile? pickedImage;
    var isUploading = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Record Correction'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: remarkController,
                    decoration: const InputDecoration(
                      labelText: 'How was it fixed?',
                      hintText: 'e.g., Tightened loose connection',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  if (widget.rootCauses.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      initialValue: selectedRootCause,
                      decoration: const InputDecoration(
                        labelText: 'Root Cause',
                        border: OutlineInputBorder(),
                      ),
                      items: widget.rootCauses.map((cause) => DropdownMenuItem(value: cause, child: Text(cause))).toList(),
                      onChanged: (val) => setDialogState(() => selectedRootCause = val),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const SizedBox(height: 16),
                  const Text('Proof of Correction:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                       final source = await _selectPhotoSource(context);
                       if (source == null) return;
                       final picker = ImagePicker();
                       final image = await picker.pickImage(source: source);
                       if (image != null) {
                         setDialogState(() {
                           pickedImage = image;
                           currentPhotoUrl = null; // Clear old if new picked
                         });
                       }
                    },
                    child: Stack(
                      children: [
                        Container(
                          height: 150,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[400]!),
                          ),
                          alignment: Alignment.center,
                          child: pickedImage != null
                              ? (kIsWeb || pickedImage!.path.startsWith('http')
                                  ? Image.network(pickedImage!.path, fit: BoxFit.cover) 
                                  : Image.file(File(pickedImage!.path), fit: BoxFit.cover))
                              : currentPhotoUrl != null
                                  ? (kIsWeb || currentPhotoUrl!.startsWith('http')
                                      ? Image.network(currentPhotoUrl!, fit: BoxFit.cover)
                                      : Image.file(File(currentPhotoUrl!), fit: BoxFit.cover))
                                  : const Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.camera_alt, color: Colors.grey, size: 40),
                                        Text('Tap to Take/Import Photo', style: TextStyle(color: Colors.grey)),
                                      ],
                                    ),
                        ),
                        if (pickedImage != null || currentPhotoUrl != null)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () {
                                setDialogState(() {
                                  pickedImage = null;
                                  currentPhotoUrl = null;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade600,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.3),
                                      blurRadius: 3,
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.close, color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isUploading)
                    const Padding(
                      padding: EdgeInsets.only(top: 16.0),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isUploading ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isUploading ? null : () async {
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  
                  if (remarkController.text.isEmpty) {
                    messenger.showSnackBar(const SnackBar(content: Text('Please enter a remark')));
                    return;
                  }
                  if (pickedImage == null && currentPhotoUrl == null) {
                    messenger.showSnackBar(const SnackBar(content: Text('Please take a proof photo')));
                    return;
                  }

                  // Offline-First: Compress and save locally, upload happens at final submission
                  var localPath = currentPhotoUrl; // Preserve existing URL if editing
                  
                  if (pickedImage != null) {
                    setDialogState(() => isUploading = true);
                    localPath = await _compressClosurePhotoLocally(pickedImage!);
                    setDialogState(() => isUploading = false);
                  }

                  if (localPath != null) {
                    // Save local path (will be uploaded at final submission)
                    widget.onAnswerChanged('closure_photo_local_path', localPath);
                    widget.onAnswerChanged('closure_photo', localPath); // For preview
                    widget.onAnswerChanged('closure_remark', remarkController.text);
                    if (selectedRootCause != null) {
                      widget.onAnswerChanged('root_cause', selectedRootCause);
                    }
                    widget.onAnswerChanged('closure_status', 'Closed');
                    widget.onAnswerChanged('is_corrected', true);
                    widget.onAnswerChanged('status', 'Not OK');

                    if (navigator.canPop()) navigator.pop();
                  } else {
                     messenger.showSnackBar(const SnackBar(content: Text('Failed to save photo')));
                  }
                },
                child: const Text('Save Correction'),
              ),
            ],
          );
        },
      ),
    );
  }
}
