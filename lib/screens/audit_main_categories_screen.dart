import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/activity_log_service.dart';
import '../services/audit_manager.dart';
import '../widgets/audit_card_widget.dart';
import 'audit_search_screen.dart';
import 'audit_sub_categories_screen.dart';
import 'audit_task_screen.dart';
import 'auditor_self_review_screen.dart';



class AuditMainCategoriesScreen extends StatefulWidget {
  final String siteName;
  final String turbineName;
  final DocumentReference turbineModelRef;
  final DocumentReference siteRef;
  final String siteId;
  final String turbineId;
  final String stateName;
  final String? planId;
  final Map<String, dynamic>? planData;

  const AuditMainCategoriesScreen({
    required this.siteName, required this.turbineName, required this.turbineModelRef, required this.siteRef, required this.siteId, required this.turbineId, required this.stateName, super.key,
    this.planId,
    this.planData,
  });

  @override
  State<AuditMainCategoriesScreen> createState() => _AuditMainCategoriesScreenState();
}

class _AuditMainCategoriesScreenState extends State<AuditMainCategoriesScreen> {

  // ── State for merged main-category list ──────────────────────────────────
  final List<QueryDocumentSnapshot> _categories = [];
  StreamSubscription<QuerySnapshot>? _subByModel;
  StreamSubscription<QuerySnapshot>? _subAllModels;

  // Track doc IDs in each stream to enable merge without duplicates
  final Set<String> _modelDocIds = {};
  final Set<String> _allModelsDocIds = {};
  bool _isLoading = true; // Track loading state

  // Cached task IDs & calculated progress stats per category to load all cards together
  final Map<String, List<String>> _categoryTaskIds = {};
  final Map<String, Map<String, int>> _categoryStats = {};
  int _statsLoadSession = 0;

  @override
  void initState() {
    super.initState();
    // Initialize AuditManager with a specific draft ID for this session
    // This prevents data mixing between different turbines/plans
    final uniqueDraftId = '${widget.planId ?? "unplanned"}_${widget.turbineId}';
    AuditManager.instance.init(draftId: uniqueDraftId);
    AuditManager.instance.saveDraftMetadata(
      draftId: uniqueDraftId,
      siteId: widget.siteId,
      siteName: widget.siteName,
      turbineId: widget.turbineId,
      turbineName: widget.turbineName,
      stateName: widget.stateName,
      modelId: widget.turbineModelRef.id,
      modelName: widget.planData?['turbine_model']?.toString() ?? '',
      planId: widget.planId,
    );

    // Subscribe to both category streams and merge results
    _subscribeToCategories();

    // Log audit start event
    ActivityLogService.instance.logActivity(
      actionType: 'AUDIT_START',
      description: 'Started audit for ${widget.siteName} - ${widget.turbineName}',
      metadata: {
        'siteId': widget.siteId,
        'siteName': widget.siteName,
        'turbineId': widget.turbineId,
        'turbineName': widget.turbineName,
        'stateName': widget.stateName,
        'planId': widget.planId,
      },
    );
  }

  /// Subscribe to two Firestore streams and merge them into [_categories].
  void _subscribeToCategories() {
    // Stream 1: categories explicitly mapped to this turbine model property target_models
    _subByModel = FirebaseFirestore.instance
        .collection('main_categories')
        .where('target_models', arrayContains: widget.turbineModelRef.id)
        // orderBy removed to bypass composite index requirement; local sorting handles this
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      _modelDocIds
        ..clear()
        ..addAll(snapshot.docs.map((d) => d.id));
      _mergeCategories(stream1Docs: snapshot.docs);
    }, onError: (Object e) {
      // Composite index not yet created – fall back to turbinemodel_ref query
      debugPrint('main_categories target_models query failed: $e');
      _subscribeToLegacyStream();
    });

    // Stream 2: categories marked as "All Models"
    _subAllModels = FirebaseFirestore.instance
        .collection('main_categories')
        .where('is_all_models', isEqualTo: true)
        // orderBy removed to bypass composite index requirement; local sorting handles this
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      _allModelsDocIds
        ..clear()
        ..addAll(snapshot.docs.map((d) => d.id));
      _mergeCategories(stream2Docs: snapshot.docs);
    }, onError: (Object e) {
      debugPrint('main_categories is_all_models query failed: $e');
      // Ensure loading state is cleared if this stream fails and no categories exist
      if (mounted && _categories.isEmpty) setState(() => _isLoading = false);
    });
  }

  /// Legacy fallback: uses the old turbinemodel_ref DocumentReference query.
  void _subscribeToLegacyStream() {
    _subByModel?.cancel();
    _subAllModels?.cancel(); // Cancel the all-models stream too since it also failed
    _subByModel = FirebaseFirestore.instance
        .collection('main_categories')
        .where('turbinemodel_ref', isEqualTo: widget.turbineModelRef)
        // orderBy removed to bypass potential index requirements; local sorting handles this
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      _categories
        ..clear()
        ..addAll(snapshot.docs);
      if (_categories.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
      } else {
        _loadAllCategoryStats();
      }
    }, onError: (Object e) {
      debugPrint('main_categories legacy query also failed: $e');
      if (mounted) setState(() => _isLoading = false);
    });
  }

  /// Merge the latest docs from both streams into [_categories], sorted by sort_order.
  void _mergeCategories({
    List<QueryDocumentSnapshot>? stream1Docs,
    List<QueryDocumentSnapshot>? stream2Docs,
  }) {
    // Keep the existing docs from the "other" stream and replace the updated one
    final merged = <String, QueryDocumentSnapshot>{};

    // Add existing categories that aren't being replaced
    for (final doc in _categories) {
      merged[doc.id] = doc;
    }

    // Update with fresh docs from whichever stream just fired
    if (stream1Docs != null) {
      for (final doc in stream1Docs) {
        merged[doc.id] = doc;
      }
      // Remove docs that disappeared from stream1
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
      // Remove docs that disappeared from stream2
      for (final id in Set<String>.from(_allModelsDocIds)) {
        if (!stream2Docs.any((d) => d.id == id)) {
          merged.remove(id);
        }
      }
    }

    // Sort by sort_order
    final sorted = merged.values.toList()
      ..sort((a, b) {
        final aOrder = (a.data() as Map<String, dynamic>)['sort_order'] ?? 0;
        final bOrder = (b.data() as Map<String, dynamic>)['sort_order'] ?? 0;
        return (aOrder as num).compareTo(bOrder as num);
      });

    _categories
      ..clear()
      ..addAll(sorted);

    if (_categories.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
    } else {
      _loadAllCategoryStats();
    }
  }

  @override
  void dispose() {
    _subByModel?.cancel();
    _subAllModels?.cancel();
    super.dispose();
  }

  Future<void> _submitFinalAudit() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // 1. Show Validation Loader
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Validating completeness...'),
          ],
        ),
      ),
    ));

    final pendingTasks = await _scanForPendingTasks();
    if (!mounted) return;
    Navigator.pop(context); // Close validation loader

    if (pendingTasks.isNotEmpty) {
      _showIncompleteAuditDialog(pendingTasks);
      return;
    }

    final allAnswers = AuditManager.instance.getAllAnswers();
    if (allAnswers.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No data to submit'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Data Preparation - deep copy
    final finalData = <String, Map<String, dynamic>>{};
    allAnswers.forEach((key, value) {
      finalData[key] = Map<String, dynamic>.from(value as Map);
    });

    // Count photos and resolve paths to verify local presence
    var totalPhotosToUpload = 0;
    var totalClosurePhotosToUpload = 0;
    var alreadyUploadedCount = 0;
    var missingFiles = 0;

    for (var taskId in finalData.keys) {
      final taskData = finalData[taskId]!;
      if (taskData.containsKey('photos') && taskData['photos'] is List) {
        final photos = List<dynamic>.from(taskData['photos'] as List);
        for (var i = 0; i < photos.length; i++) {
          final path = photos[i].toString();
          if (path.startsWith('http://') || path.startsWith('https://')) {
            alreadyUploadedCount++;
          } else {
            if (!kIsWeb) {
              final resolved = await _resolvePhotoFile(path);
              if (resolved != null) {
                photos[i] = resolved.path; // Update to exact resolved path
                totalPhotosToUpload++;
              } else {
                missingFiles++;
                debugPrint('⚠️ Missing photo file: $path');
              }
            } else {
              totalPhotosToUpload++;
            }
          }
        }
        taskData['photos'] = photos;
      }
      if (taskData.containsKey('closure_photo_local_path')) {
        final path = taskData['closure_photo_local_path'].toString();
        if (path.isNotEmpty) {
          if (path.startsWith('http://') || path.startsWith('https://')) {
            alreadyUploadedCount++;
          } else {
            if (!kIsWeb) {
              final resolved = await _resolvePhotoFile(path);
              if (resolved != null) {
                taskData['closure_photo_local_path'] = resolved.path;
                totalClosurePhotosToUpload++;
              } else {
                missingFiles++;
                debugPrint('⚠️ Missing closure photo file: $path');
              }
            } else {
              totalClosurePhotosToUpload++;
            }
          }
        }
      }
    }

    final grandTotal = totalPhotosToUpload + totalClosurePhotosToUpload + alreadyUploadedCount;
    
    // Warn if files are missing (likely due to app reinstall)
    if (missingFiles > 0) {
      debugPrint('🚨 WARNING: $missingFiles photo files are missing from device!');
      messenger.showSnackBar(
        SnackBar(
          content: Text('Warning: $missingFiles photos could not be found. They may have been deleted.'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
    }

    // Progress tracking with ValueNotifier
    final uploadProgress = ValueNotifier<Map<String, dynamic>>({
      'current': alreadyUploadedCount,
      'total': grandTotal,
      'status': (totalPhotosToUpload + totalClosurePhotosToUpload) > 0 ? 'Preparing photo upload...' : 'Saving to server...',
    });

    // Show progress dialog
    if (!mounted) return;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ValueListenableBuilder<Map<String, dynamic>>(
        valueListenable: uploadProgress,
        builder: (context, progress, _) {
          final current = progress['current'] as int;
          final total = progress['total'] as int;
          final status = progress['status'] as String;
          final progressValue = total > 0 ? current / total : 0.0;
          
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Circular progress with percentage inside
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: CircularProgressIndicator(
                        value: total > 0 ? progressValue : null,
                        strokeWidth: 6,
                        backgroundColor: Colors.grey[200],
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00897B)),
                      ),
                    ),
                    if (total > 0)
                      Text(
                        '${(progressValue * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00897B),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  total > 0 ? 'Uploading Photos: $current / $total' : 'Uploading Audit...',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  status,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (total > 0)
                  LinearProgressIndicator(
                    value: progressValue,
                    backgroundColor: Colors.grey[200],
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00897B)),
                  ),
              ],
            ),
          );
        },
      ),
    ));

    try {
      var completedCount = alreadyUploadedCount;

      // MULTI-PASS ROBUST UPLOAD LOOP (Up to 3 passes across all tasks)
      const maxPasses = 3;
      for (var pass = 1; pass <= maxPasses; pass++) {
        var anyUploadInThisPass = false;

        // 1. Process standard task photos (Dedicated bandwidth / Sequential)
        for (var taskId in finalData.keys) {
          final taskData = finalData[taskId]!;
          if (!taskData.containsKey('photos') || taskData['photos'] is! List) continue;

          final currentList = List<String>.from((taskData['photos'] as List).map((e) => e.toString()));
          var taskUpdated = false;

          for (var i = 0; i < currentList.length; i++) {
            final photoPath = currentList[i];
            if (photoPath.startsWith('http://') || photoPath.startsWith('https://')) {
              continue; // Already on server
            }

            anyUploadInThisPass = true;
            uploadProgress.value = {
              'current': completedCount,
              'total': grandTotal,
              'status': pass > 1 
                  ? 'Retrying photo ${completedCount + 1}/$grandTotal (Pass $pass)...' 
                  : 'Uploading photo ${completedCount + 1}/$grandTotal...',
            };

            final downloadUrl = await _uploadPhotoWithRetry(
              photoPath, 
              taskId,
              photoType: 'obs_$i',
              onStatusUpdate: (msg) {
                uploadProgress.value = {
                  'current': completedCount,
                  'total': grandTotal,
                  'status': 'Photo ${completedCount + 1}/$grandTotal: $msg',
                };
              },
            );

            if (downloadUrl != null) {
              currentList[i] = downloadUrl;
              taskUpdated = true;
              completedCount++;
              uploadProgress.value = {
                'current': completedCount,
                'total': grandTotal,
                'status': 'Uploaded photo $completedCount of $grandTotal',
              };
            }
          }

          if (taskUpdated) {
            taskData['photos'] = currentList;
            // IMMEDIATELY SAVE PROGRESS: Uploaded URLs are preserved, local paths remain for retries
            AuditManager.instance.saveAnswer(taskId, taskData);
          }
        }

        // 2. Process closure photos (for offline-first deviation corrections)
        for (var taskId in finalData.keys) {
          final taskData = finalData[taskId]!;
          if (!taskData.containsKey('closure_photo_local_path')) continue;
          final localPath = taskData['closure_photo_local_path'].toString();
          if (localPath.isEmpty || localPath.startsWith('http://') || localPath.startsWith('https://')) {
            continue;
          }

          anyUploadInThisPass = true;
          uploadProgress.value = {
            'current': completedCount,
            'total': grandTotal,
            'status': pass > 1 
                ? 'Retrying closure photo (Pass $pass)...' 
                : 'Uploading closure photo...',
          };

          final downloadUrl = await _uploadPhotoWithRetry(
            localPath, 
            taskId,
            photoType: 'closure',
            onStatusUpdate: (msg) {
              uploadProgress.value = {
                'current': completedCount,
                'total': grandTotal,
                'status': 'Closure photo: $msg',
              };
            },
          );

          if (downloadUrl != null) {
            taskData['closure_photo'] = downloadUrl;
            taskData.remove('closure_photo_local_path');
            completedCount++;
            AuditManager.instance.saveAnswer(taskId, taskData);
            uploadProgress.value = {
              'current': completedCount,
              'total': grandTotal,
              'status': 'Closure photo uploaded',
            };
          }
        }

        if (!anyUploadInThisPass) {
          break; // Everything was already uploaded
        }

        // Check if any local photos still remain
        var hasLocalPending = false;
        for (var td in finalData.values) {
          if (td.containsKey('photos') && td['photos'] is List) {
            for (var p in (td['photos'] as List)) {
              if (!p.toString().startsWith('http://') && !p.toString().startsWith('https://')) {
                hasLocalPending = true;
                break;
              }
            }
          }
          if (td.containsKey('closure_photo_local_path')) {
            final p = td['closure_photo_local_path'].toString();
            if (!p.startsWith('http://') && !p.startsWith('https://')) {
              hasLocalPending = true;
            }
          }
          if (hasLocalPending) break;
        }

        if (!hasLocalPending) {
          break; // 100% of photos uploaded!
        }

        if (pass < maxPasses) {
          uploadProgress.value = {
            'current': completedCount,
            'total': grandTotal,
            'status': 'Stabilizing connection before retry (Pass ${pass + 1})...',
          };
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }

      // ── STRICT ZERO-PHOTO-LOSS VERIFICATION GATE ──
      final remainingFailedPhotos = <String>[];
      for (var entry in finalData.entries) {
        final td = entry.value;
        if (td.containsKey('photos') && td['photos'] is List) {
          for (var p in (td['photos'] as List)) {
            final str = p.toString();
            if (!str.startsWith('http://') && !str.startsWith('https://')) {
              remainingFailedPhotos.add(str);
            }
          }
        }
        if (td.containsKey('closure_photo_local_path')) {
          final str = td['closure_photo_local_path'].toString();
          if (!str.startsWith('http://') && !str.startsWith('https://')) {
            remainingFailedPhotos.add(str);
          }
        }
      }

      if (remainingFailedPhotos.isNotEmpty) {
        // ABORT SUBMISSION! DO NOT COMMIT TO FIRESTORE! DO NOT CLEAR AUDIT!
        if (navigator.canPop()) navigator.pop(); // Close upload progress dialog

        if (!mounted) return;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogCtx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 28),
                SizedBox(width: 10),
                Text('Upload Incomplete', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${remainingFailedPhotos.length} photo(s) could not be uploaded due to weak or unstable network.',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 12),
                const Text(
                  '🛡️ All your audit data and photos are safely preserved on this device. '
                  'No photos have been lost, and successfully uploaded photos won\'t need to be re-uploaded.',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                Text(
                  'Please check your cellular signal or Wi-Fi and tap "Retry Upload Now" to complete your audit submission.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Save & Finish Later'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  // Resumes upload immediately - only failed photos will be uploaded!
                  _submitFinalAudit();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00897B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry Upload Now', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        return;
      }

      // Update status for Firestore operations
      uploadProgress.value = {
        'current': grandTotal,
        'total': grandTotal,
        'status': 'Saving to server...',
      };

      // Get current user details
      final currentUser = FirebaseAuth.instance.currentUser;
      final auditorId = currentUser?.uid;
      var auditorName = currentUser?.displayName ?? currentUser?.email;
      final auditorEmail = currentUser?.email;

      // Fetch correct auditor name from users collection
      if (auditorId != null) {
        try {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(auditorId).get();
          if (userDoc.exists && userDoc.data() != null) {
             final userData = userDoc.data() as Map<String, dynamic>;
             if (userData.containsKey('name') && userData['name'] != null && (userData['name'] as String).isNotEmpty) {
               auditorName = userData['name'] as String;
             }
          }
        } catch (e) {
          debugPrint('Error fetching user details: $e');
        }
      }

      // Resolve State ID and Turbine Model Name
      var stateId = '';
      DocumentReference? stateRef;
      var turbineModelName = '';

      // Try getting from Plan Data first
      if (widget.planData != null) {
        if (widget.planData!['state_ref'] is DocumentReference) {
           stateRef = widget.planData!['state_ref'] as DocumentReference;
           stateId = stateRef.id;
        }
        if (widget.planData!['turbine_model'] != null) {
           turbineModelName = widget.planData!['turbine_model'] as String;
        }
      }

      // Fetch if missing
      if (stateId.isEmpty || turbineModelName.isEmpty) {
        try {
           if (stateId.isEmpty) {
             final siteDoc = await widget.siteRef.get();
             if (siteDoc.exists) {
               final data = siteDoc.data() as Map<String, dynamic>;
                if (data['state_ref'] is DocumentReference) {
                  stateRef = data['state_ref'] as DocumentReference;
                  stateId = stateRef.id;
                }
             }
           }
           
           if (turbineModelName.isEmpty) {
             final modelDoc = await widget.turbineModelRef.get();
             if (modelDoc.exists) {
               final data = modelDoc.data() as Map<String, dynamic>;
               turbineModelName = (data['turbine_model'] as String?) ?? 'Unknown Model';
             }
           }
        } catch (e) {
          debugPrint('Error fetching additional audit details: $e');
        }
      }

      // ── WriteBatch: Atomic Firestore Commit ──
      final batch = FirebaseFirestore.instance.batch();

      // Pre-reserve the audit document reference (auto-ID)
      final DocumentReference auditDocRef = FirebaseFirestore.instance.collection('audit_submissions').doc();

      batch.set(auditDocRef, {
        // 1. Core Levels (Schema-Hardened)
        'state_id': stateId,
        'state_name': widget.stateName,
        'state_ref': stateRef,
        'site_id': widget.siteRef.id,
        'site_name': widget.siteName,
        'site_ref': widget.siteRef,
        'turbine_model_id': widget.turbineModelRef.id,
        'turbine_model_name': turbineModelName,
        'turbinemodel_ref': widget.turbineModelRef,
        'turbine_id': widget.turbineId, // Schema Hardening: was missing

        // 2. Existing Data
        'site': widget.siteName,
        'turbine': widget.turbineName,
        'state': widget.stateName,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending_self_review',
        'auditor_id': auditorId,
        'auditor_name': auditorName,
        'auditor_email': auditorEmail,
        'audit_data': finalData,
        // Data Enrichment for Web Dashboard Compatibility
        'wtg_rating': '',
        'customer_name': '',
        'commissioning_date': null,
        'date_of_take_over': null,
        'plan_date_maintenance': null,
        'actual_date_maintenance': null,
        'report_metadata': <String, dynamic>{},
        'plan_id': widget.planId,
        'is_planned': widget.planId != null,
        'is_unplanned': widget.planId == null,
      });

      uploadProgress.value = {
        'current': grandTotal,
        'total': grandTotal,
        'status': 'Generating NC documents...',
      };

      // Generate NC documents — added to WriteBatch for atomicity
      var batchOpCount = 1; // Already includes the audit doc
      const batchLimit = 490; // Firestore limit is 500, leave buffer

      for (var taskId in finalData.keys) {
        final taskData = finalData[taskId]!;
        final status = taskData['status'];
        final isCorrected = taskData['is_corrected'] == true;
        
        if ((status != null && status != 'OK') || isCorrected) {
          try {
            // Fetch task document to get category info
            final taskDoc = await FirebaseFirestore.instance
                .collection('tasks')
                .doc(taskId)
                .get();
            
            if (taskDoc.exists) {
              final taskInfo = taskDoc.data()!;
              final subCategoryRef = taskInfo['sub_categories_ref'] as DocumentReference;
              final subCategoryDoc = await subCategoryRef.get();
              
              var categoryName = 'Unknown';
              if (subCategoryDoc.exists) {
                final mainCategoryRef = subCategoryDoc.get('main_categories_ref') as DocumentReference;
                final mainCategoryDoc = await mainCategoryRef.get();
                if (mainCategoryDoc.exists) {
                  categoryName = mainCategoryDoc.get('name') as String;
                }
              }
              
              // Get the first photo URL if available
              var evidencePhotoUrl = '';
              if (taskData.containsKey('photos') && taskData['photos'] is List) {
                final photos = taskData['photos'] as List;
                if (photos.isNotEmpty) {
                  evidencePhotoUrl = photos[0] as String;
                }
              }
              
              // If batch is full, commit and start a new one
              if (batchOpCount >= batchLimit) {
                await batch.commit();
                batchOpCount = 0;
              }

              // Add NC to batch
              final ncDocRef = FirebaseFirestore.instance.collection('ncs').doc();
              batch.set(ncDocRef, {
                'audit_ref': auditDocRef.id,
                'site_ref': widget.siteRef,
                'site_name': widget.siteName,
                'turbine_id': widget.turbineName,
                'category': categoryName,
                'problem_description': (taskData['observation'] as String?) ?? '',
                'nc_status': isCorrected ? 'Closed' : 'open',
                'evidence_photo_url': evidencePhotoUrl,
                'auditor_id': auditorId,
                'auditor_name': auditorName,
                'created_at': FieldValue.serverTimestamp(),
                // Include OSC details for Closed NCs
                if (isCorrected) ...{
                  'closure_remark': (taskData['closure_remark'] as String?) ?? '',
                  'closure_photo_url': (taskData['closure_photo'] as String?) ?? '',
                  'closure_date': FieldValue.serverTimestamp(),
                }
              });
              batchOpCount++;
            }
          } catch (e) {
            // Log error but don't fail the entire submission
            debugPrint('Error creating NC document for task $taskId: $e');
          }
        }
      }

      // ── Commit the atomic batch ──
      await batch.commit();

      // Cleanup
      await AuditManager.instance.clearAudit();

      // Update Plan Status if applicable
      if (widget.planId != null) {
        try {
          await FirebaseFirestore.instance
              .collection('planning_data')
              .doc(widget.planId)
              .update({
            'status': 'completed',
            'linked_audit_id': auditDocRef.id,
            'completed_at': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          debugPrint('Error updating plan status: $e');
        }
      }

      navigator.pop(); // Close loading dialog
      
      // Log successful audit submission
      await ActivityLogService.instance.logActivity(
        actionType: 'AUDIT_SUBMIT',
        description: 'Submitted audit for ${widget.siteName} - ${widget.turbineName}',
        metadata: {
          'siteId': widget.siteId,
          'siteName': widget.siteName,
          'turbineId': widget.turbineId,
          'turbineName': widget.turbineName,
          'auditId': auditDocRef.id,
          'planId': widget.planId,
        },
      );
      
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Audit Submitted Successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      navigator.pop(); // Return to Dashboard

    } catch (e) {
      navigator.pop(); // Close loading dialog
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error submitting audit: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Safely resolves a local photo file path, including container changes on app updates/restarts
  Future<File?> _resolvePhotoFile(String path) async {
    if (kIsWeb) return null;
    try {
      final directFile = File(path);
      if (await directFile.exists()) {
        return directFile;
      }
      final appDir = await getApplicationDocumentsDirectory();
      final baseName = p.basename(path);
      final fallbackFile = File(p.join(appDir.path, baseName));
      if (await fallbackFile.exists()) {
        return fallbackFile;
      }
    } catch (e) {
      debugPrint('Error resolving photo file: $e');
    }
    return null;
  }

  /// Upload a single photo with resilient retry logic, deterministic path, and exponential backoff
  Future<String?> _uploadPhotoWithRetry(
    String path, 
    String taskId, {
    int maxRetries = 5,
    String photoType = 'task',
    void Function(String)? onStatusUpdate,
  }) async {
    // If it's already a URL, return it immediately
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }

    // Clean site and turbine names for a neat, stable storage path
    final cleanSite = widget.siteName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final cleanTurbine = widget.turbineName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final baseName = p.basenameWithoutExtension(path);
    // Deterministic storage path ensures resumability and clean overwrites across retries
    final storagePath = 'audit_images/${cleanSite}_$cleanTurbine/${taskId}_${photoType}_$baseName.jpg';
    final ref = FirebaseStorage.instance.ref().child(storagePath);

    File? resolvedFile;
    if (!kIsWeb) {
      resolvedFile = await _resolvePhotoFile(path);
      if (resolvedFile == null || !await resolvedFile.exists()) {
        debugPrint('❌ Photo file does not exist locally: $path');
        return null;
      }
      final fileSize = await resolvedFile.length();
      if (fileSize == 0) {
        debugPrint('❌ Photo file is empty (0 bytes): $path');
        return null;
      }
    }

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint('🔄 Upload attempt $attempt/$maxRetries for: $path');
        onStatusUpdate?.call('Uploading (Attempt $attempt)...');

        if (kIsWeb) {
          final xFile = XFile(path);
          final fileBytes = await xFile.readAsBytes().timeout(const Duration(seconds: 15));
          final uploadTask = ref.putData(
            fileBytes,
            SettableMetadata(contentType: 'image/jpeg'),
          );
          final snapshot = await uploadTask.timeout(const Duration(seconds: 60));
          if (snapshot.state != TaskState.success) {
            debugPrint('❌ Web upload not success. State: ${snapshot.state}');
            continue;
          }
        } else {
          final uploadTask = ref.putFile(
            resolvedFile!,
            SettableMetadata(contentType: 'image/jpeg'),
          );
          final snapshot = await uploadTask.timeout(const Duration(seconds: 60));
          if (snapshot.state != TaskState.success || snapshot.bytesTransferred == 0) {
            debugPrint('❌ Mobile upload not success. State: ${snapshot.state}, bytes: ${snapshot.bytesTransferred}');
            continue;
          }
        }

        // Fetch download URL with timeout
        final downloadUrl = await ref.getDownloadURL().timeout(const Duration(seconds: 30));
        debugPrint('✅ Photo uploaded successfully: $storagePath -> ${downloadUrl.substring(0, min(50, downloadUrl.length))}...');
        return downloadUrl;

      } catch (e) {
        debugPrint('⚠️ Upload attempt $attempt failed for $path: $e');
        if (attempt == maxRetries) {
          debugPrint('❌ Failed to upload after $maxRetries attempts: $path');
          return null;
        }
        // Adaptive exponential backoff: 1s, 2s, 4s, 8s, 12s
        final delayMs = min(12000, 1000 * (1 << (attempt - 1)));
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }
    return null;
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
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.siteName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  widget.turbineName,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            actions: [
              // Search Button
              IconButton(
                icon: const Icon(Icons.search_rounded, color: Colors.white),
                tooltip: 'Search Checkpoints',
                onPressed: () {
                  final uniqueDraftId = '${widget.planId ?? "unplanned"}_${widget.turbineId}';
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => AuditSearchScreen(
                        turbineModelRef: widget.turbineModelRef,
                        draftId: uniqueDraftId,
                      ),
                    ),
                  ).then((_) => _recalculateStatsFromLocal());
                },
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Center(
                  child: ElevatedButton.icon(
                    onPressed: _navigateToSelfReview,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Review & Submit'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF00897B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _buildCategoriesBody(),
    );
  }

  /// Navigate to Self-Review screen before submission
  Future<void> _navigateToSelfReview() async {
    // Show validation loader
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Calculating completeness...', style: TextStyle(fontFamily: 'Outfit')),
          ],
        ),
      ),
    ));

    // Calculate pending and total tasks
    final pendingTasks = await _scanForPendingTasks();
    await AuditManager.instance.flush();
    final allAnswers = AuditManager.instance.getAllAnswers();
    
    final pendingCount = pendingTasks.length;
    final totalTasks = allAnswers.length + pendingCount;

    if (!mounted) return;
    Navigator.pop(context); // Close loader

    final typedAnswers = <String, Map<String, dynamic>>{};
    allAnswers.forEach((key, value) {
      if (value is Map) {
        typedAnswers[key] = Map<String, dynamic>.from(value);
      }
    });

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AuditorSelfReviewScreen(
          auditData: typedAnswers,
          siteName: widget.siteName,
          turbineName: widget.turbineName,
          totalTasks: totalTasks,
          pendingCount: pendingCount,
          onConfirmSubmit: _submitFinalAudit,
        ),
      ),
    );
    _recalculateStatsFromLocal();
  }

  /// Body widget — reads from the merged [_categories] list.
  /// Uses CustomScrollView with SliverStickyHeader for pinned category headers.
  Widget _buildCategoriesBody() {
    if (_isLoading) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.3,
        ),
        itemCount: 6,
        itemBuilder: (context, index) => const AuditCardSkeleton(),
      );
    }

    if (_categories.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No categories found for this model', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
            const SizedBox(height: 8),
            const Text('Check "is_all_models" or "target_models" in Firestore', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }

    final uniqueDraftId = '${widget.planId ?? "unplanned"}_${widget.turbineId}';

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.3, // Wider cards
      ),
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final doc = _categories[index];
        final data = doc.data() as Map<String, dynamic>;
        final categoryName = (data['name'] as String?) ?? 'Unknown';

        final stats = _categoryStats[doc.id] ?? {'total': 0, 'ok': 0, 'notOk': 0, 'na': 0};
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
                builder: (context) => AuditSubCategoriesScreen(
                  parentCategoryName: categoryName,
                  mainCategoryRef: doc.reference,
                  turbineModelRef: widget.turbineModelRef,
                  turbineId: widget.turbineId,
                  draftId: uniqueDraftId,
                ),
              ),
            ).then((_) => _recalculateStatsFromLocal());
          },
        );
      },
    );
  }

  /// Concurrently loads tasks for all categories so all cards show up at once without skeletons popping in piecemeal.
  Future<void> _loadAllCategoryStats() async {
    final sessionId = ++_statsLoadSession;
    final allAnswers = AuditManager.instance.getAllAnswers();

    try {
      final results = await Future.wait(
        _categories.map((catDoc) => _fetchTaskIdsForCategory(catDoc.reference)),
      );

      if (!mounted || sessionId != _statsLoadSession) return;

      final newStats = <String, Map<String, int>>{};
      for (var i = 0; i < _categories.length; i++) {
        final catId = _categories[i].id;
        final taskIds = results[i];
        _categoryTaskIds[catId] = taskIds;
        newStats[catId] = _computeStatsFromTaskIds(taskIds, allAnswers);
      }

      setState(() {
        _categoryStats.addAll(newStats);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading category stats: $e');
      if (mounted && sessionId == _statsLoadSession) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Fetches all task IDs belonging to the applicable subcategories of a main category in parallel.
  Future<List<String>> _fetchTaskIdsForCategory(DocumentReference mainCatRef) async {
    final subCatsSnapshot = await FirebaseFirestore.instance
        .collection('sub_categories')
        .where('main_categories_ref', isEqualTo: mainCatRef)
        .get();

    final applicableSubs = subCatsSnapshot.docs.where((subDoc) {
      final subData = subDoc.data();
      final isAllModels = subData['is_all_models'] == true;
      final targetModels = (subData['target_models'] as List<dynamic>?) ?? [];
      return isAllModels || targetModels.contains(widget.turbineModelRef.id);
    }).toList();

    if (applicableSubs.isEmpty) return const [];

    final taskSnapshots = await Future.wait(
      applicableSubs.map((sub) => FirebaseFirestore.instance
          .collection('tasks')
          .where('sub_categories_ref', isEqualTo: sub.reference)
          .get()
      ),
    );

    final taskIds = <String>[];
    for (final snap in taskSnapshots) {
      for (final doc in snap.docs) {
        taskIds.add(doc.id);
      }
    }
    return taskIds;
  }

  /// Fast in-memory calculation of progress from task IDs and local answers.
  Map<String, int> _computeStatsFromTaskIds(List<String> taskIds, Map<String, dynamic> allAnswers) {
    var okCount = 0;
    var notOkCount = 0;
    var naCount = 0;

    for (final taskId in taskIds) {
      if (allAnswers.containsKey(taskId)) {
        final taskData = allAnswers[taskId] as Map<String, dynamic>?;
        final status = taskData?['status'];
        if (status == 'OK') {
          okCount++;
        } else if (status == 'Not OK') {
          notOkCount++;
        } else if (status == 'NA') {
          naCount++;
        }
      }
    }

    return {
      'total': taskIds.length,
      'ok': okCount,
      'notOk': notOkCount,
      'na': naCount,
    };
  }

  /// Instantly updates progress badges from local AuditManager data without network overhead.
  void _recalculateStatsFromLocal() {
    final allAnswers = AuditManager.instance.getAllAnswers();
    setState(() {
      for (final entry in _categoryTaskIds.entries) {
        _categoryStats[entry.key] = _computeStatsFromTaskIds(entry.value, allAnswers);
      }
    });
  }


  void _showIncompleteAuditDialog(List<Map<String, dynamic>> pendingTasks) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade200,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.warning_rounded, color: Colors.red.shade700, size: 28),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Incomplete Audit',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            Text(
                              'Please complete all tasks before submitting',
                              style: TextStyle(color: Colors.black54, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // List of Tasks
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: pendingTasks.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final task = pendingTasks[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    title: Text(
                      task['title'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ref: ${task['reference']}',
                            style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Category: ${task['main_category_name']}',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.orange),
                    ),
                    onTap: () {
                      Navigator.pop(context); // Close bottom sheet
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (context) => AuditTaskScreen(
                            subCategoryName: task['sub_category_name'] as String,
                            subCategoryRef: task['sub_category_ref'] as DocumentReference,
                            mainCategoryName: task['main_category_name'] as String,
                            mainCategoryRef: task['main_category_ref'] as DocumentReference,
                            initialTaskId: task['id'] as String,
                          ),
                        ),
                      ).then((_) => _recalculateStatsFromLocal());
                    },
                  );
                },
              ),
            ),
            
            // Bottom Button
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                    foregroundColor: Colors.black87,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Back to Audit'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _scanForPendingTasks() async {
    final pendingTasks = <Map<String, dynamic>>[];
    
    // AuditManager is already initialized in initState() with correct draftId
    final allAnswers = AuditManager.instance.getAllAnswers();
    
    // 1. Get all Main Categories for this turbine model (new + legacy schema)

    Future<QuerySnapshot> fetchByModelId() => FirebaseFirestore.instance
        .collection('main_categories')
        .where('target_models', arrayContains: widget.turbineModelRef.id)
        .get();

    Future<QuerySnapshot> fetchAllModels() => FirebaseFirestore.instance
        .collection('main_categories')
        .where('is_all_models', isEqualTo: true)
        .get();

    Future<QuerySnapshot> fetchLegacy() => FirebaseFirestore.instance
        .collection('main_categories')
        .where('turbinemodel_ref', isEqualTo: widget.turbineModelRef)
        .get();

    // Merge results from all three queries (deduplicate by doc ID)
    final mergedMainCats = <String, QueryDocumentSnapshot>{};
    try {
      final results = await Future.wait([
        fetchByModelId(),
        fetchAllModels(),
        fetchLegacy(),
      ]);
      for (final qs in results) {
        for (final doc in qs.docs) {
          mergedMainCats[doc.id] = doc;
        }
      }
    } catch (e) {
      debugPrint('_scanForPendingTasks query error: $e');
    }

    // Sort by sort_order
    final mainCategoriesDocs = mergedMainCats.values.toList()
      ..sort((a, b) {
        final aO = (a.data() as Map<String, dynamic>)['sort_order'] ?? 0;
        final bO = (b.data() as Map<String, dynamic>)['sort_order'] ?? 0;
        return (aO as num).compareTo(bO as num);
      });

    // Iterate directly over the merged, sorted list
    for (var mainCatDoc in mainCategoriesDocs) {
      final mainCatName = mainCatDoc.get('name')?.toString() ?? 'Unknown';
      
      // 2. Get Sub Categories
      final subCatsQuery = await FirebaseFirestore.instance
          .collection('sub_categories')
          .where('main_categories_ref', isEqualTo: mainCatDoc.reference)
          .get();
          
      for (var subCatDoc in subCatsQuery.docs) {
        final subData = subCatDoc.data();
        final isAllModels = subData['is_all_models'] == true;
        final targetModels = (subData['target_models'] as List<dynamic>?) ?? [];
        final isApplicable = isAllModels || targetModels.contains(widget.turbineModelRef.id);
        if (!isApplicable) continue;

        final subCatName = subCatDoc.get('name')?.toString() ?? 'Unknown';
        
        // 3. Get Tasks
        final tasksQuery = await FirebaseFirestore.instance
            .collection('tasks')
            .where('sub_categories_ref', isEqualTo: subCatDoc.reference)
            .get();
        
        for (var taskDoc in tasksQuery.docs) {
          final taskId = taskDoc.id;
          final taskData = taskDoc.data();
          final answer = allAnswers[taskId] as Map<String, dynamic>?;
          final status = answer?['status'];
          
          if (status == null || status.toString().isEmpty) {
            pendingTasks.add({
              'id': taskId,
              'title': taskData['title'] as String,
              'reference': taskData['referenceoftask']?.toString() ?? 'N/A',
              'main_category_name': mainCatName,
              'main_category_ref': mainCatDoc.reference,
              'sub_category_name': subCatName,
              'sub_category_ref': subCatDoc.reference,
            });
          }
        }
      }
    }
    return pendingTasks;
  }
}
