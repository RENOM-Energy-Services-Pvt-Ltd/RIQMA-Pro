import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../providers/app_settings_provider.dart';
import '../../services/audit_manager.dart';

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

class AddNewNcScreen extends StatefulWidget {
  final String mainCategoryName;
  final DocumentReference mainCategoryRef;
  final String? initialSubCategoryName;
  final DocumentReference? initialSubCategoryRef;
  final String? initialReference;
  final String? turbineId;
  final DocumentReference? turbineModelRef;
  final String? draftId;
  final String? initialTaskId;
  final Map<String, dynamic>? initialData;

  const AddNewNcScreen({
    required this.mainCategoryName,
    required this.mainCategoryRef,
    super.key,
    this.initialSubCategoryName,
    this.initialSubCategoryRef,
    this.initialReference,
    this.turbineId,
    this.turbineModelRef,
    this.draftId,
    this.initialTaskId,
    this.initialData,
  });

  @override
  State<AddNewNcScreen> createState() => _AddNewNcScreenState();
}

class _AddNewNcScreenState extends State<AddNewNcScreen> {
  late final String _taskId;
  late TextEditingController _subCategoryController;
  late TextEditingController _titleController;
  late TextEditingController _observationController;
  late TextEditingController _closureRemarkController;

  String? _selectedReference;
  final List<String> _references = [];
  bool _isLoadingReferences = true;

  // Status is null by default: Neither OK nor Not OK is pre-selected
  String? _status;
  String? _subStatus;
  String? _selectedRootCause;
  final List<String> _photos = [];
  bool _isCorrected = false;
  String? _closurePhotoPath;

  List<String> _rootCauses = [];

  @override
  void initState() {
    super.initState();
    _taskId = widget.initialTaskId ?? 'custom_nc_${DateTime.now().millisecondsSinceEpoch}';

    final data = widget.initialData ?? AuditManager.instance.getAnswer(_taskId) ?? {};

    _subCategoryController = TextEditingController(
      text: (data['sub_category_name'] as String?) ?? widget.initialSubCategoryName ?? '',
    );
    _titleController = TextEditingController(
      text: (data['question'] as String?) ?? (data['title'] as String?) ?? 'New Checkpoint',
    );
    _observationController = TextEditingController(
      text: (data['observation'] as String?) ?? '',
    );
    _closureRemarkController = TextEditingController(
      text: (data['closure_remark'] as String?) ?? '',
    );

    _selectedReference = (data['reference_name'] as String?) ??
        (data['referenceoftask'] as String?) ??
        widget.initialReference;

    if (data.containsKey('status') && data['status'] != null && data['status'].toString().isNotEmpty) {
      _status = data['status'].toString();
    } else {
      _status = null; // Unselected by default
    }

    if (data.containsKey('sub_status') && data['sub_status'] != null) {
      _subStatus = data['sub_status']?.toString();
    } else {
      _subStatus = null;
    }
    if (data.containsKey('root_cause')) {
      _selectedRootCause = data['root_cause']?.toString();
    }
    if (data.containsKey('photos') && data['photos'] is List) {
      _photos.addAll(List<String>.from(data['photos'] as List));
    }
    if (data['is_corrected'] == true) {
      _isCorrected = true;
    }
    _closurePhotoPath = (data['closure_photo_local_path'] as String?) ?? (data['closure_photo'] as String?);

    _fetchReferences();
    _fetchRootCauses();
  }

  @override
  void dispose() {
    _subCategoryController.dispose();
    _titleController.dispose();
    _observationController.dispose();
    _closureRemarkController.dispose();
    super.dispose();
  }

  Future<void> _fetchReferences() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('references').get();
      if (mounted) {
        final list = <String>[];
        for (var doc in snap.docs) {
          final name = (doc.data()['name'] as String?)?.trim();
          if (name != null && name.isNotEmpty && !list.contains(name)) {
            list.add(name);
          }
        }
        list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        setState(() {
          _references.addAll(list);
          _isLoadingReferences = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching references: $e');
      if (mounted) {
        setState(() => _isLoadingReferences = false);
      }
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

  void _openReferencePicker() {
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _ReferencePickerSheet(
        references: _references,
        selectedReference: _selectedReference,
        onSelected: (ref) {
          setState(() {
            _selectedReference = ref;
          });
        },
      ),
    );
  }

  Future<void> _capturePhoto() async {
    try {
      final source = await _selectPhotoSource(context);
      if (source == null) return;

      final picker = ImagePicker();
      final image = await picker.pickImage(source: source);
      if (image == null) return;

      String finalPath;
      if (kIsWeb) {
        finalPath = image.path;
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        final fileName = '${_taskId}_obs_${_photos.length}_${DateTime.now().millisecondsSinceEpoch}.jpg';
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
        } catch (e) {
          debugPrint('⚠️ Image compression error: $e');
        }

        if (savedPath == null) {
          try {
            final original = File(image.path);
            if (await original.exists()) {
              final copied = await original.copy(targetPath);
              savedPath = copied.path;
            } else {
              savedPath = image.path;
            }
          } catch (_) {
            savedPath = image.path;
          }
        }
        finalPath = savedPath;
      }

      setState(() {
        _photos.add(finalPath);
      });
    } catch (e) {
      debugPrint('❌ Error capturing photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to attach photo: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<String?> _compressClosurePhotoLocally(XFile imageFile) async {
    if (kIsWeb) return imageFile.path;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = '${_taskId}_closure_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final targetPath = p.join(appDir.path, fileName);

      try {
        final compressedFile = await FlutterImageCompress.compressAndGetFile(
          imageFile.path,
          targetPath,
          quality: 85,
        );
        if (compressedFile != null && await File(compressedFile.path).exists()) {
          return compressedFile.path;
        }
      } catch (compressErr) {
        debugPrint('⚠️ Closure image compression failed: $compressErr, falling back to copy');
      }

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
    final remarkController = TextEditingController(text: _closureRemarkController.text);
    var currentPhotoUrl = _closurePhotoPath;
    var selectedRootCause = _selectedRootCause;
    XFile? pickedImage;
    var isUploading = false;
    var markAsOk = _status == 'OK';

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
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
                  if (_rootCauses.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      initialValue: selectedRootCause,
                      decoration: const InputDecoration(
                        labelText: 'Root Cause',
                        border: OutlineInputBorder(),
                      ),
                      items: _rootCauses.map((cause) => DropdownMenuItem(value: cause, child: Text(cause))).toList(),
                      onChanged: (val) => setDialogState(() => selectedRootCause = val),
                    ),
                    const SizedBox(height: 16),
                  ],
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
                          currentPhotoUrl = null;
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Mark Task as OK?'),
                      const Spacer(),
                      Switch(
                        value: markAsOk,
                        activeTrackColor: Colors.green.withValues(alpha: 0.5),
                        activeThumbColor: Colors.green,
                        onChanged: (val) {
                          setDialogState(() {
                            markAsOk = val;
                          });
                        },
                      ),
                    ],
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
                onPressed: isUploading
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);

                        if (remarkController.text.trim().isEmpty) {
                          messenger.showSnackBar(const SnackBar(content: Text('Please enter a remark')));
                          return;
                        }
                        if (pickedImage == null && currentPhotoUrl == null) {
                          messenger.showSnackBar(const SnackBar(content: Text('Please take a proof photo')));
                          return;
                        }

                        var localPath = currentPhotoUrl;
                        if (pickedImage != null) {
                          setDialogState(() => isUploading = true);
                          localPath = await _compressClosurePhotoLocally(pickedImage!);
                          setDialogState(() => isUploading = false);
                        }

                        if (localPath != null) {
                          setState(() {
                            _closureRemarkController.text = remarkController.text.trim();
                            _closurePhotoPath = localPath;
                            if (selectedRootCause != null) {
                              _selectedRootCause = selectedRootCause;
                            }
                            _isCorrected = true;
                            if (markAsOk) {
                              _status = 'OK';
                              _subStatus = null;
                            }
                          });

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

  Future<void> _confirmAndRemovePhoto(String path) async {
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
      setState(() {
        _photos.remove(path);
      });
    }
  }

  void _showFullImage(String path) {
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

  bool _validateForm() {
    final subCatName = _subCategoryController.text.trim();
    if (subCatName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Sub-Category name'), backgroundColor: Colors.red),
      );
      return false;
    }

    if (_selectedReference == null || _selectedReference!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a Reference'), backgroundColor: Colors.red),
      );
      return false;
    }

    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checkpoint title is required'), backgroundColor: Colors.red),
      );
      return false;
    }

    if (_status == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select status (OK / NOT OK / NA)'), backgroundColor: Colors.red),
      );
      return false;
    }

    final appSettings = Provider.of<AppSettingsProvider>(context, listen: false);
    final observation = _observationController.text.trim();

    if (appSettings.mandatoryObservationText && observation.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Observation is mandatory'), backgroundColor: Colors.red),
      );
      return false;
    }

    if (_status == 'Not OK') {
      if (_photos.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please attach at least one photo for "Not OK" status'), backgroundColor: Colors.red),
        );
        return false;
      }

      if (_subStatus == null || _subStatus!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select severity level (Aobs, MCF, CF)'), backgroundColor: Colors.red),
        );
        return false;
      }

      if (appSettings.restrictNavWithoutDetails && observation.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Observation is required for "Not OK" status'), backgroundColor: Colors.red),
        );
        return false;
      }

      if (_isCorrected && (_closurePhotoPath == null || _closurePhotoPath!.isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please attach proof photo for On-Spot Correction'), backgroundColor: Colors.red),
        );
        return false;
      }
    }

    return true;
  }

  Future<void> _saveCheckpoint() async {
    if (!_validateForm()) return;

    final subCatName = _subCategoryController.text.trim();
    final subCatId = widget.initialSubCategoryRef?.id ??
        'custom_sub_${subCatName.replaceAll(RegExp(r'\s+'), '_').toLowerCase()}';

    final dataToSave = <String, dynamic>{
      'id': _taskId,
      'is_custom_nc': true,
      'question': _titleController.text.trim(),
      'title': _titleController.text.trim(),
      'description': '',
      'main_category_name': widget.mainCategoryName,
      'main_category_id': widget.mainCategoryRef.id,
      'main_category_ref': widget.mainCategoryRef,
      'sub_category_name': subCatName,
      'sub_category_id': subCatId,
      if (widget.initialSubCategoryRef != null) 'sub_categories_ref': widget.initialSubCategoryRef,
      'reference_name': _selectedReference ?? 'General',
      'referenceoftask': _selectedReference ?? 'General',
      'status': _status,
      'sub_status': _status == 'Not OK' ? _subStatus : null,
      'observation': _observationController.text.trim(),
      'remarks': '',
      'root_cause': _selectedRootCause,
      'photos': _photos,
      'is_corrected': _isCorrected,
      if (widget.turbineId != null) 'turbine_id': widget.turbineId,
      'timestamp': DateTime.now().toIso8601String(),
    };

    if (_isCorrected) {
      dataToSave['closure_remark'] = _closureRemarkController.text.trim();
      if (_closurePhotoPath != null) {
        if (_closurePhotoPath!.startsWith('http')) {
          dataToSave['closure_photo'] = _closurePhotoPath;
        } else {
          dataToSave['closure_photo_local_path'] = _closurePhotoPath;
        }
      }
    }

    // Save into AuditManager (Local persistent file)
    AuditManager.instance.saveAnswer(_taskId, dataToSave);
    await AuditManager.instance.flush();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Checkpoint / NC Saved Successfully!'),
        backgroundColor: Color(0xFF00897B),
        duration: Duration(seconds: 2),
      ),
    );

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          // Header Bar (Matches AuditTaskScreen header gradient & layout)
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 8,
              bottom: 12,
              left: 16,
              right: 16,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A237E), Color(0xFF00E5FF)],
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
                        _subCategoryController.text.trim().isNotEmpty
                            ? _subCategoryController.text.trim()
                            : 'Add New Checkpoint',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
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

          // Form Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Card 1: Category & Checkpoint Name Details
                  _buildElectricCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sub-Category Name (Typeable)
                        TextField(
                          controller: _subCategoryController,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Outfit',
                          ),
                          decoration: InputDecoration(
                            labelText: 'Sub-Category Name',
                            hintText: 'Enter sub-category name',
                            labelStyle: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
                            ),
                            filled: true,
                            fillColor: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Reference Selection Field
                        InkWell(
                          onTap: _openReferencePicker,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Reference',
                                        style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _selectedReference != null && _selectedReference!.isNotEmpty
                                            ? _selectedReference!
                                            : 'Tap to select reference',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'Outfit',
                                          color: _selectedReference != null
                                              ? Theme.of(context).colorScheme.onSurface
                                              : Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_isLoadingReferences)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                else
                                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Checkpoint Title
                        TextField(
                          controller: _titleController,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Outfit',
                          ),
                          decoration: InputDecoration(
                            labelText: 'Checkpoint Name',
                            labelStyle: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
                            ),
                            filled: true,
                            fillColor: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Card 2: Status Selection (Matches AuditTaskScreen exactly)
                  _buildElectricCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Status',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A237E),
                            fontFamily: 'Outfit',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatusButton(
                                label: 'OK',
                                isSelected: _status == 'OK',
                                color: const Color(0xFF388E3C),
                                icon: Icons.check_circle_outline,
                                onTap: () {
                                  setState(() {
                                    _status = 'OK';
                                    _subStatus = null;
                                  });
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
                                      isSelected: _status == 'Not OK',
                                      color: const Color(0xFFD32F2F),
                                      icon: Icons.cancel_outlined,
                                      onTap: () {
                                        setState(() {
                                          _status = 'Not OK';
                                        });
                                      },
                                    ),
                                  ),
                                  if (_isCorrected)
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
                                              'Fixed',
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
                                isSelected: _status == 'NA',
                                color: Colors.grey.shade600,
                                icon: Icons.do_not_disturb_alt,
                                onTap: () {
                                  setState(() {
                                    _status = 'NA';
                                    _subStatus = null;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),

                        // Severity Levels (Aobs, MCF, CF)
                        if (_status == 'Not OK') ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatusButton(
                                  label: 'Aobs',
                                  isSelected: _subStatus == 'Aobs',
                                  color: Colors.amber.shade700,
                                  icon: Icons.warning_amber_rounded,
                                  compact: true,
                                  onTap: () => setState(() => _subStatus = 'Aobs'),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _buildStatusButton(
                                  label: 'MCF',
                                  isSelected: _subStatus == 'MCF',
                                  color: Colors.blue.shade700,
                                  icon: Icons.info_outline,
                                  compact: true,
                                  onTap: () => setState(() => _subStatus = 'MCF'),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _buildStatusButton(
                                  label: 'CF',
                                  isSelected: _subStatus == 'CF',
                                  color: Colors.red.shade700,
                                  icon: Icons.error_outline,
                                  compact: true,
                                  onTap: () => setState(() => _subStatus = 'CF'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Card 3: Photos (Matches AuditTaskScreen photo card exactly)
                  _buildElectricCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Photos',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A237E),
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                                if (_status == 'Not OK')
                                  const Text(' *', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${_photos.length} Attached',
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
                              ..._photos.map((path) => Padding(
                                    padding: const EdgeInsets.only(right: 14.0, top: 6.0),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        GestureDetector(
                                          onTap: () => _showFullImage(path),
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
                                            onTap: () => _confirmAndRemovePhoto(path),
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
                              if (_photos.length < 3)
                                 Padding(
                                  padding: const EdgeInsets.only(top: 6.0),
                                  child: GestureDetector(
                                    onTap: _capturePhoto,
                                    child: Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF5F7FA),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.add_a_photo_outlined, color: Color(0xFF00E5FF), size: 24),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Add Photo',
                                            style: TextStyle(fontSize: 9, color: Colors.grey[600], fontWeight: FontWeight.bold),
                                          ),
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

                  // Card 4: Observation Notes (Matches AuditTaskScreen notes card)
                  _buildElectricCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Observation Notes',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A237E),
                            fontFamily: 'Outfit',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _observationController,
                          maxLines: 3,
                          style: const TextStyle(fontSize: 14, fontFamily: 'Outfit'),
                          decoration: InputDecoration(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Observation'),
                                if (_status == 'Not OK')
                                  const Text(' *', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
                            ),
                            filled: true,
                            fillColor: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Card 5: Root Cause Dropdown (If available)
                  if (_rootCauses.isNotEmpty) ...[
                    _buildElectricCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Root Cause Analysis',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A237E),
                              fontFamily: 'Outfit',
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedRootCause,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Select Root Cause',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
                              ),
                              filled: true,
                              fillColor: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: null,
                                child: Text('None / Select later'),
                              ),
                              ..._rootCauses.map((rc) => DropdownMenuItem<String>(
                                    value: rc,
                                    child: Text(rc, style: const TextStyle(fontSize: 13, fontFamily: 'Outfit')),
                                  )),
                            ],
                            onChanged: (val) => setState(() => _selectedRootCause = val),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Card 6: Deviation Corrected Button (Matches AuditTaskScreen exactly)
                  if (_status == 'Not OK' || _isCorrected) ...[
                    _buildElectricCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _isCorrected ? Icons.check_circle : Icons.build_circle,
                                color: _isCorrected ? Colors.green : Colors.orange,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _isCorrected ? 'Deviation Corrected On-Spot' : 'Fix Deviation Now?',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: _isCorrected ? Colors.green[800] : Colors.orange[900],
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_isCorrected) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Remark: ${_closureRemarkController.text.isNotEmpty ? _closureRemarkController.text : "-"}',
                              style: TextStyle(color: Colors.grey[800], fontFamily: 'Outfit'),
                            ),
                            const SizedBox(height: 8),
                            // View Proof Button
                            if (_closurePhotoPath != null)
                              OutlinedButton.icon(
                                onPressed: () => _showFullImage(_closurePhotoPath!),
                                icon: const Icon(Icons.image),
                                label: const Text('View Proof'),
                              ),
                          ],
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _showCorrectionDialog,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isCorrected ? Colors.grey[200] : const Color(0xFF00E5FF),
                              foregroundColor: _isCorrected ? Colors.black : Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                              _isCorrected ? 'Edit Correction' : 'Record On-Spot Correction',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),

      // Bottom Bar (Matches AuditTaskScreen clean styling)
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _saveCheckpoint,
              icon: const Icon(Icons.check_circle_outline, size: 20),
              label: const Text(
                'Save Checkpoint / NC',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
                foregroundColor: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
            ),
          ),
        ),
      ),
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
      padding: const EdgeInsets.all(18.0),
      child: child,
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
    return InkWell(
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
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
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
  }
}

/// Modern Searchable Reference Picker Bottom Sheet
class _ReferencePickerSheet extends StatefulWidget {
  final List<String> references;
  final String? selectedReference;
  final ValueChanged<String> onSelected;

  const _ReferencePickerSheet({
    required this.references,
    required this.selectedReference,
    required this.onSelected,
  });

  @override
  State<_ReferencePickerSheet> createState() => _ReferencePickerSheetState();
}

class _ReferencePickerSheetState extends State<_ReferencePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = List.from(widget.references);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onFilter(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = List.from(widget.references);
      } else {
        _filtered = widget.references.where((r) => r.toLowerCase().contains(q)).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.70,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const Text(
                    'Select Reference',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextField(
                controller: _searchController,
                onChanged: _onFilter,
                style: const TextStyle(fontSize: 14, fontFamily: 'Outfit'),
                decoration: InputDecoration(
                  hintText: 'Search reference (e.g. Safety, ISO, WTG)...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _onFilter('');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
                  ),
                  filled: true,
                  fillColor: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
            const Divider(height: 16),

            // Reference List
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text(
                            'No matching references',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                          ),
                          if (_searchController.text.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: () {
                                final customRef = _searchController.text.trim();
                                widget.onSelected(customRef);
                                Navigator.pop(context);
                              },
                              icon: const Icon(Icons.add, size: 18),
                              label: Text('Use "${_searchController.text.trim()}" as Reference'),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (context, index) {
                        final ref = _filtered[index];
                        final isSelected = widget.selectedReference == ref;
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                          leading: Icon(
                            isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                            color: isSelected ? const Color(0xFF00897B) : Colors.grey,
                            size: 20,
                          ),
                          title: Text(
                            ref,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected ? const Color(0xFF00897B) : Theme.of(context).colorScheme.onSurface,
                              fontFamily: 'Outfit',
                            ),
                          ),
                          onTap: () {
                            widget.onSelected(ref);
                            Navigator.pop(context);
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
}
