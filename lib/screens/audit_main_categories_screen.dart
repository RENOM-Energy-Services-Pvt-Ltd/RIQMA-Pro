import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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
  final Set<String> _expandedCategories = {}; // Track expanded/collapsed state
  StreamSubscription<QuerySnapshot>? _subByModel;
  StreamSubscription<QuerySnapshot>? _subAllModels;

  // Track doc IDs in each stream to enable merge without duplicates
  final Set<String> _modelDocIds = {};
  final Set<String> _allModelsDocIds = {};
  bool _isLoading = true; // Track loading state

  @override
  void initState() {
    super.initState();
    // Initialize AuditManager with a specific draft ID for this session
    // This prevents data mixing between different turbines/plans
    final uniqueDraftId = '${widget.planId ?? "unplanned"}_${widget.turbineId}';
    AuditManager.instance.init(draftId: uniqueDraftId);

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
    final currentModelId = widget.turbineModelRef.id;

    // Stream 1: categories explicitly mapped to this turbine model
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
      // Ensure loading state is cleared even if this stream fails
      if (mounted) setState(() => _isLoading = false);
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
      setState(() {
        _categories
          ..clear()
          ..addAll(snapshot.docs);
        _isLoading = false;
      });
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

    setState(() {
      _categories
        ..clear()
        ..addAll(sorted);
      _isLoading = false; // Mark as done after first merge
    });
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
    showDialog<void>(
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
    );

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

    // Count total photos to upload (excluding already uploaded URLs)
    // Also validate that local files actually exist
    var totalPhotos = 0;
    var totalClosurePhotos = 0;
    var missingFiles = 0;
    
    for (var taskId in finalData.keys) {
      final taskData = finalData[taskId]!;
      if (taskData.containsKey('photos')) {
        final photos = (taskData['photos'] as List<dynamic>?) ?? [];
        for (var photo in photos) {
          final path = photo.toString();
          if (!path.startsWith('http')) {
            // Check if file exists (mobile only)
            if (!kIsWeb) {
              final file = File(path);
              if (file.existsSync()) {
                totalPhotos++;
              } else {
                missingFiles++;
                debugPrint('⚠️ Missing photo file: $path');
              }
            } else {
              totalPhotos++;
            }
          }
        }
      }
      if (taskData.containsKey('closure_photo_local_path')) {
        final path = taskData['closure_photo_local_path'] as String;
        if (!path.startsWith('http')) {
          if (!kIsWeb) {
            final file = File(path);
            if (file.existsSync()) {
              totalClosurePhotos++;
            } else {
              missingFiles++;
              debugPrint('⚠️ Missing closure photo file: $path');
            }
          } else {
            totalClosurePhotos++;
          }
        }
      }
    }

    final grandTotal = totalPhotos + totalClosurePhotos;
    
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
      'current': 0,
      'total': grandTotal,
      'status': 'Preparing upload...',
    });

    // Show progress dialog
    if (!mounted) return;
    showDialog<void>(
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
    );

    try {
      var uploadedCount = 0;

      // BATCHED IMAGE UPLOAD LOOP
      const batchSize = 3; // Process 3 photos at a time
      
      for (var taskId in finalData.keys) {
        final taskData = finalData[taskId]!;
        if (taskData.containsKey('photos')) {
          final localPaths = List<String>.from((taskData['photos'] as List<dynamic>?) ?? []);
          final downloadUrls = <String>[];
          
          // Filter out already-uploaded URLs
          final pathsToUpload = <String>[];
          for (var path in localPaths) {
            if (path.startsWith('http')) {
              downloadUrls.add(path); // Already uploaded
            } else {
              pathsToUpload.add(path);
            }
          }
          
          // Process in batches
          var failedCount = 0;
          for (var i = 0; i < pathsToUpload.length; i += batchSize) {
            final batch = pathsToUpload.sublist(i, min(i + batchSize, pathsToUpload.length));
            
            // Upload batch in parallel
            final batchResults = await Future.wait(
              batch.map((path) => _uploadPhotoWithRetry(path, taskId)),
            );
            
            // Collect successful uploads and count failures
            for (var result in batchResults) {
              if (result != null) {
                downloadUrls.add(result);
              } else {
                failedCount++;
              }
            }
            
            // Update progress
            uploadedCount += batch.length;
            final statusText = failedCount > 0 
              ? 'Uploading... ($failedCount failed)' 
              : 'Processing task photos...';
            uploadProgress.value = {
              'current': uploadedCount,
              'total': grandTotal,
              'status': statusText,
            };
          }
          
          if (failedCount > 0) {
            debugPrint('⚠️ Task $taskId: $failedCount photos failed to upload');
          }
          
          // Replace local paths with download URLs
          taskData['photos'] = downloadUrls;

          // SAVE PROGRESS: Update local storage with URLs immediately
          // This ensures that if the app crashes now, the next retry will see URLs
          // and skip re-uploading.
          AuditManager.instance.saveAnswer(taskId, taskData);
        }
      }

      // Closure Photo Upload Loop (for Offline-First Deviation Correction)
      for (var taskId in finalData.keys) {
        final taskData = finalData[taskId]!;
        if (taskData.containsKey('closure_photo_local_path')) {
          final localPath = taskData['closure_photo_local_path'] as String;
          // Check if it's a local path (not already a URL)
          if (!localPath.startsWith('http')) {
            uploadProgress.value = {
              'current': uploadedCount,
              'total': grandTotal,
              'status': 'Uploading closure photo...',
            };
            
            try {
              final fileName = '${taskId}_closure_${DateTime.now().millisecondsSinceEpoch}.jpg';
              final storagePath = 'audit_closures/${widget.siteName.replaceAll(' ', '_')}_${widget.turbineName.replaceAll(' ', '_')}/$fileName';
              final ref = FirebaseStorage.instance.ref().child(storagePath);
              
              if (kIsWeb) {
                final xFile = XFile(localPath);
                final fileBytes = await xFile.readAsBytes();
                await ref.putData(fileBytes, SettableMetadata(contentType: 'image/jpeg'));
              } else {
                final file = File(localPath);
                if (await file.exists()) {
                  await ref.putFile(file);
                }
              }
              
              final url = await ref.getDownloadURL();
              taskData['closure_photo'] = url;
            } catch (e) {
              debugPrint('Error uploading closure photo for task $taskId: $e');
            }
            
            uploadedCount++;
            uploadProgress.value = {
              'current': uploadedCount,
              'total': grandTotal,
              'status': 'Closure photo uploaded',
            };
          }
          // Clean up temporary field
          taskData.remove('closure_photo_local_path');
        }
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

  /// Upload a single photo with retry logic and exponential backoff
  Future<String?> _uploadPhotoWithRetry(String path, String taskId, {int maxRetries = 3}) async {
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        // Add random component to filename to prevent collisions
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${path.hashCode}.jpg';
        final storagePath = 'audit_images/$fileName';
        final ref = FirebaseStorage.instance.ref().child(storagePath);
        
        debugPrint('🔄 Upload attempt $attempt for: $path');
        
        if (kIsWeb) {
          // Web: Upload file bytes to Firebase Storage
          final xFile = XFile(path);
          
          Uint8List fileBytes;
          try {
            fileBytes = await xFile.readAsBytes();
            debugPrint('📊 File size (web): ${fileBytes.length} bytes');
          } catch (readErr) {
            debugPrint('❌ Error reading file (Dead Blob?): $readErr');
            return null; 
          }
          
          final uploadTask = ref.putData(
            fileBytes,
            SettableMetadata(contentType: 'image/jpeg'),
          );
          
          // Wait for upload and check result
          final snapshot = await uploadTask;
          debugPrint('📦 Upload state: ${snapshot.state}');
          
          if (snapshot.state != TaskState.success) {
            debugPrint('❌ Upload did not succeed. State: ${snapshot.state}');
            continue; // Retry
          }
        } else {
          // Mobile: Upload file to Firebase Storage
          final file = File(path);
          if (await file.exists()) {
            final fileSize = await file.length();
            debugPrint('📤 Uploading file: $path ($fileSize bytes)');
            
            if (fileSize == 0) {
              debugPrint('❌ File is empty (0 bytes): $path');
              return null;
            }
            
            final uploadTask = ref.putFile(file);
            
            // Wait for upload and check result
            final snapshot = await uploadTask;
            debugPrint('📦 Upload state: ${snapshot.state}, bytes transferred: ${snapshot.bytesTransferred}');
            
            if (snapshot.state != TaskState.success) {
              debugPrint('❌ Upload did not succeed. State: ${snapshot.state}');
              continue; // Retry
            }
            
            if (snapshot.bytesTransferred == 0) {
              debugPrint('❌ Zero bytes transferred for: $path');
              continue; // Retry
            }
            
            debugPrint('✅ Upload completed: ${snapshot.bytesTransferred} bytes transferred');
          } else {
            debugPrint('❌ File does not exist: $path');
            return null; // File doesn't exist, no point retrying
          }
        }
        
        // Get download URL
        final downloadUrl = await ref.getDownloadURL();
        debugPrint('🔗 Download URL obtained: ${downloadUrl.substring(0, 50)}...');
        return downloadUrl;
        
      } catch (e, stackTrace) {
        debugPrint('⚠️ Upload attempt $attempt failed for task $taskId');
        debugPrint('   Error type: ${e.runtimeType}');
        debugPrint('   Error message: $e');
        debugPrint('   Stack trace: ${stackTrace.toString().split('\n').take(3).join('\n')}');
        
        if (attempt == maxRetries) {
          debugPrint('❌ Failed to upload after $maxRetries attempts');
          return null;
        }
        // Exponential backoff: 500ms, 1000ms, 2000ms...
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
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
                  ).then((_) => setState(() {}));
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
    await AuditManager.instance.flush();
    final allAnswers = AuditManager.instance.getAllAnswers();
    final typedAnswers = <String, Map<String, dynamic>>{};
    allAnswers.forEach((key, value) {
      if (value is Map) {
        typedAnswers[key] = Map<String, dynamic>.from(value);
      }
    });

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AuditorSelfReviewScreen(
          auditData: typedAnswers,
          siteName: widget.siteName,
          turbineName: widget.turbineName,
          onConfirmSubmit: _submitFinalAudit,
        ),
      ),
    );
  }

  /// Body widget — reads from the merged [_categories] list.
  /// Uses CustomScrollView with SliverStickyHeader for pinned category headers.
  Widget _buildCategoriesBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
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

        return FutureBuilder<Map<String, int>>(
          future: _calculateProgress(doc.reference),
          builder: (context, snapshot) {
            final stats = snapshot.data ?? {'total': 0, 'ok': 0, 'notOk': 0, 'na': 0};
            final total = stats['total'] ?? 0;
            final ok = stats['ok'] ?? 0;
            final notOk = stats['notOk'] ?? 0;
            final na = stats['na'] ?? 0;
            final completed = ok + notOk + na;
            final pending = total - completed;

            final uniqueDraftId = '${widget.planId ?? "unplanned"}_${widget.turbineId}';

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
                ).then((_) => setState(() {}));
              },
            );
          },
        );
      },
    );
  }



  Future<Map<String, int>> _calculateSubCategoryProgressDirect(DocumentReference subCategoryRef) async {
    final allAnswers = AuditManager.instance.getAllAnswers();
    final tasksSnapshot = await FirebaseFirestore.instance
        .collection('tasks')
        .where('sub_categories_ref', isEqualTo: subCategoryRef)
        .get();

    final total = tasksSnapshot.docs.length;
    var okCount = 0, notOkCount = 0, naCount = 0;
    for (var taskDoc in tasksSnapshot.docs) {
      final taskId = taskDoc.id;
      if (allAnswers.containsKey(taskId)) {
        final status = allAnswers[taskId]?['status'];
        if (status == 'OK') {
          okCount++;
        } else if (status == 'Not OK') notOkCount++;
        else if (status == 'NA') naCount++;
      }
    }
    return {'total': total, 'ok': okCount, 'notOk': notOkCount, 'na': naCount};
  }

  Future<Map<String, int>> _calculateProgress(DocumentReference mainCategoryRef) async {
    final allAnswers = AuditManager.instance.getAllAnswers();
    var totalTasks = 0;
    var okCount = 0;
    var notOkCount = 0;
    var naCount = 0;
    
    final subCategoriesSnapshot = await FirebaseFirestore.instance
        .collection('sub_categories')
        .where('main_categories_ref', isEqualTo: mainCategoryRef)
        .get();
    
    for (var subCategoryDoc in subCategoriesSnapshot.docs) {
      final tasksSnapshot = await FirebaseFirestore.instance
          .collection('tasks')
          .where('sub_categories_ref', isEqualTo: subCategoryDoc.reference)
          .get();
      
      totalTasks += tasksSnapshot.docs.length;
      
      for (var taskDoc in tasksSnapshot.docs) {
        final taskId = taskDoc.id;
        if (allAnswers.containsKey(taskId)) {
          final status = allAnswers[taskId]?['status'];
          if (status == 'OK') {
            okCount++;
          } else if (status == 'Not OK') {
            notOkCount++;
          } else if (status == 'NA') {
            naCount++;
          }
        }
      }
    }
    
    return {'total': totalTasks, 'ok': okCount, 'notOk': notOkCount, 'na': naCount};
  }


  Future<void> _showStatusDetails(BuildContext context, String categoryName, DocumentReference mainCategoryRef, String statusFilter) async {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              '$statusFilter Tasks - $categoryName',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _fetchFilteredTasks(mainCategoryRef, statusFilter),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  
                  final tasks = snapshot.data ?? [];
                  if (tasks.isEmpty) {
                    return const Center(child: Text('No tasks found.'));
                  }

                  return ListView.builder(
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return ListTile(
                        title: Text((task['title'] as String?) ?? 'Unknown Task'),
                        subtitle: Text((task['reference'] as String?) ?? 'No Reference'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          Navigator.pop(context); // Close bottom sheet
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (context) => AuditTaskScreen(
                                subCategoryName: task['sub_category_name'] as String,
                                subCategoryRef: task['sub_category_ref'] as DocumentReference<Object?>,
                                mainCategoryName: categoryName,
                                mainCategoryRef: mainCategoryRef,
                                initialTaskId: task['id'] as String,
                              ),
                            ),
                          ).then((_) => setState(() {}));
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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
                      ).then((_) => setState(() {}));
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
    final currentModelId = widget.turbineModelRef.id;

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
        final subCatName = subCatDoc.get('name')?.toString() ?? 'Unknown';
        
        // 3. Get Tasks
        final tasksQuery = await FirebaseFirestore.instance
            .collection('tasks')
            .where('sub_categories_ref', isEqualTo: subCatDoc.reference)
            .get();
        
        for (var taskDoc in tasksQuery.docs) {
          final taskId = taskDoc.id;
          final taskData = taskDoc.data();
          final answer = allAnswers[taskId];
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

  Future<List<Map<String, dynamic>>> _fetchFilteredTasks(DocumentReference mainCategoryRef, String statusFilter) async {
    // AuditManager is already initialized in initState() with correct draftId
    final allAnswers = AuditManager.instance.getAllAnswers();
    final filteredTasks = <Map<String, dynamic>>[];

    // Get all subcategories
    final subCategoriesSnapshot = await FirebaseFirestore.instance
        .collection('sub_categories')
        .where('main_categories_ref', isEqualTo: mainCategoryRef)
        .get();

    for (var subCategoryDoc in subCategoriesSnapshot.docs) {
      final subCategoryName = subCategoryDoc.get('name') as String;
      
      final tasksSnapshot = await FirebaseFirestore.instance
          .collection('tasks')
          .where('sub_categories_ref', isEqualTo: subCategoryDoc.reference)
          .orderBy('sort_order')
          .get();

      for (var taskDoc in tasksSnapshot.docs) {
        final taskId = taskDoc.id;
        final taskData = taskDoc.data();
        final answer = allAnswers[taskId];
        final status = answer?['status'];

        var matches = false;
        if (statusFilter == 'Not OK') {
          matches = status == 'Not OK';
        } else if (statusFilter == 'Pending') {
          matches = status == null || (status != 'OK' && status != 'Not OK');
        }

        if (matches) {
          // Resolve reference name (simplified for list view)
          var referenceName = 'N/A';
          if (taskData.containsKey('referenceoftask')) {
            referenceName = taskData['referenceoftask'].toString();
          }

          filteredTasks.add({
            'id': taskId,
            'title': taskData['title'] as String,
            'reference': referenceName,
            'sub_category_name': subCategoryName,
            'sub_category_ref': subCategoryDoc.reference,
          });
        }
      }
    }
    return filteredTasks;
  }

  Widget _buildStatusPill(String text, Color bgColor, Color textColor, {VoidCallback? onTap}) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: textColor.withValues(alpha: 0.3), width: 1), // Subtle border
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: pill,
      );
    }
    return pill;
  }
}
