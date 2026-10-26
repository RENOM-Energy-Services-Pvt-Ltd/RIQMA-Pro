import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../providers/app_settings_provider.dart';
import '../../services/audit_manager.dart';

class AddNewNcScreen extends StatefulWidget {
  final String mainCategoryName;
  final DocumentReference mainCategoryRef;
  final String subCategoryName;
  final DocumentReference? subCategoryRef;
  final String defaultReference;
  final String? turbineId;
  final DocumentReference? turbineModelRef;
  final String? draftId;
  final String? initialTaskId;
  final Map<String, dynamic>? initialData;

  const AddNewNcScreen({
    required this.mainCategoryName,
    required this.mainCategoryRef,
    required this.subCategoryName,
    required this.defaultReference,
    super.key,
    this.subCategoryRef,
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
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _observationController;
  late TextEditingController _remarksController;
  late TextEditingController _closureRemarkController;

  String _status = 'Not OK'; // Default to Not OK for adding new NC
  String? _subStatus = 'MCF'; // Default severity
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

    _titleController = TextEditingController(
      text: (data['question'] as String?) ?? (data['title'] as String?) ?? 'New Checkpoint',
    );
    _descController = TextEditingController(
      text: (data['description'] as String?) ?? '',
    );
    _observationController = TextEditingController(
      text: (data['observation'] as String?) ?? '',
    );
    _remarksController = TextEditingController(
      text: (data['remarks'] as String?) ?? '',
    );
    _closureRemarkController = TextEditingController(
      text: (data['closure_remark'] as String?) ?? '',
    );

    if (data.containsKey('status')) {
      _status = data['status']?.toString() ?? 'Not OK';
    }
    if (data.containsKey('sub_status')) {
      _subStatus = data['sub_status']?.toString();
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

    _fetchRootCauses();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _observationController.dispose();
    _remarksController.dispose();
    _closureRemarkController.dispose();
    super.dispose();
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
          return;
        }
      }
    } catch (e) {
      debugPrint('Error fetching root causes: $e');
    }
  }

  Future<ImageSource?> _selectPhotoSource() async {
    final appSettings = Provider.of<AppSettingsProvider>(context, listen: false);
    if (!appSettings.allowGalleryImport) {
      return ImageSource.camera;
    }

    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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

  Future<void> _capturePhoto({bool isClosure = false}) async {
    try {
      final source = await _selectPhotoSource();
      if (source == null) return;

      final picker = ImagePicker();
      final image = await picker.pickImage(source: source);
      if (image == null) return;

      String finalPath;
      if (kIsWeb) {
        finalPath = image.path;
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        final tag = isClosure ? 'closure' : 'obs_${_photos.length}';
        final fileName = '${_taskId}_${tag}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final targetPath = p.join(appDir.path, fileName);

        String? savedPath;
        try {
          final compressedFile = await FlutterImageCompress.compressAndGetFile(
            image.path,
            targetPath,
            quality: 70,
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
        if (isClosure) {
          _closurePhotoPath = finalPath;
        } else {
          _photos.add(finalPath);
        }
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

    if (shouldRemove == true && mounted) {
      setState(() {
        _photos.remove(path);
      });
      if (!kIsWeb) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
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
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _validateForm() {
    final appSettings = Provider.of<AppSettingsProvider>(context, listen: false);
    final observation = _observationController.text.trim();

    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checkpoint title is required'), backgroundColor: Colors.red),
      );
      return false;
    }

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

    final subCatId = widget.subCategoryRef?.id ??
        'custom_sub_${widget.subCategoryName.replaceAll(RegExp(r'\s+'), '_').toLowerCase()}';

    final dataToSave = <String, dynamic>{
      'id': _taskId,
      'is_custom_nc': true,
      'question': _titleController.text.trim(),
      'title': _titleController.text.trim(),
      'description': _descController.text.trim(),
      'main_category_name': widget.mainCategoryName,
      'main_category_id': widget.mainCategoryRef.id,
      'main_category_ref': widget.mainCategoryRef,
      'sub_category_name': widget.subCategoryName,
      'sub_category_id': subCatId,
      if (widget.subCategoryRef != null) 'sub_categories_ref': widget.subCategoryRef,
      'reference_name': widget.defaultReference,
      'referenceoftask': widget.defaultReference,
      'status': _status,
      'sub_status': _status == 'Not OK' ? _subStatus : null,
      'observation': _observationController.text.trim(),
      'remarks': _remarksController.text.trim(),
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

    // Save into AuditManager
    AuditManager.instance.saveAnswer(_taskId, dataToSave);
    await AuditManager.instance.flush();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('New Checkpoint / NC Saved Successfully!'),
        backgroundColor: Color(0xFF00897B),
        duration: Duration(seconds: 2),
      ),
    );

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          // Header Bar
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
                // Default Reference Tag
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white30, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bookmark_outline, size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        'Ref: ${widget.defaultReference}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Outfit',
                        ),
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
                  // Card 1: Checkpoint Title & Description
                  _buildCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A237E).withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.playlist_add_check_rounded, color: Color(0xFF1A237E), size: 18),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Checkpoint Details',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A237E),
                                fontFamily: 'Outfit',
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.orange.shade200),
                              ),
                              child: Text(
                                'Custom NC',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _titleController,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Outfit',
                          ),
                          decoration: InputDecoration(
                            labelText: 'Task / Checkpoint Name *',
                            labelStyle: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                            prefixIcon: const Icon(Icons.label_outline, size: 20),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _descController,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 13, fontFamily: 'Outfit'),
                          decoration: InputDecoration(
                            labelText: 'Task Description (Optional)',
                            hintText: 'Blank by default - add details if needed',
                            labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                            prefixIcon: const Icon(Icons.description_outlined, size: 20),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Card 2: Status Selection
                  _buildCard(
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
                                          _subStatus ??= 'MCF';
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
                          const Text(
                            'NC Severity Level *',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          const SizedBox(height: 8),
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
                  const SizedBox(height: 16),

                  // Card 3: Photos
                  _buildCard(
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
                                    fontSize: 16,
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
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${_photos.length} Attached',
                                style: TextStyle(fontSize: 11, color: Colors.grey[700], fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ..._photos.map((path) => Padding(
                                    padding: const EdgeInsets.only(right: 12.0, top: 4.0),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        GestureDetector(
                                          onTap: () => _showFullImage(path),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.grey.shade300),
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(7),
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
                                                        child: const Icon(Icons.broken_image, color: Colors.grey),
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
                                                        child: const Icon(Icons.broken_image, color: Colors.grey),
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
                                              child: const Icon(Icons.close, size: 14, color: Colors.white),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )),
                              if (_photos.length < 4)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: GestureDetector(
                                    onTap: () => _capturePhoto(isClosure: false),
                                    child: Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF5F7FA),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(0xFF00E5FF).withValues(alpha: 0.6),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.add_a_photo_outlined, color: Color(0xFF00897B), size: 26),
                                          const SizedBox(height: 4),
                                          Text('Add Photo', style: TextStyle(fontSize: 10, color: Colors.grey[700], fontWeight: FontWeight.bold)),
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
                  const SizedBox(height: 16),

                  // Card 4: Observation Notes
                  _buildCard(
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
                                const Text('Observation / Problem Description'),
                                if (_status == 'Not OK')
                                  const Text(' *', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            alignLabelWithHint: true,
                            prefixIcon: const Padding(
                              padding: EdgeInsets.only(bottom: 40),
                              child: Icon(Icons.visibility_outlined, color: Color(0xFF1A237E), size: 20),
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _remarksController,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 14, fontFamily: 'Outfit'),
                          decoration: InputDecoration(
                            labelText: 'Remarks / Additional Notes',
                            alignLabelWithHint: true,
                            prefixIcon: const Padding(
                              padding: EdgeInsets.only(bottom: 20),
                              child: Icon(Icons.comment_outlined, color: Color(0xFF1A237E), size: 20),
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Card 5: Root Cause Dropdown
                  if (_rootCauses.isNotEmpty) ...[
                    _buildCard(
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
                              prefixIcon: const Icon(Icons.account_tree_outlined, color: Color(0xFF1A237E), size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                    const SizedBox(height: 16),
                  ],

                  // Card 6: On-Spot Correction (OSC)
                  if (_status == 'Not OK') ...[
                    _buildCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _isCorrected ? Icons.check_circle_rounded : Icons.build_circle_outlined,
                                color: _isCorrected ? Colors.green : Colors.orange,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _isCorrected ? 'Deviation Corrected On-Spot' : 'Fix Deviation On-Spot?',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: _isCorrected ? Colors.green.shade800 : Colors.black87,
                                        fontFamily: 'Outfit',
                                      ),
                                    ),
                                    Text(
                                      _isCorrected ? 'Marked as corrected on-site' : 'Capture proof if defect was fixed immediately',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _isCorrected,
                                activeThumbColor: Colors.green,
                                onChanged: (val) => setState(() => _isCorrected = val),
                              ),
                            ],
                          ),
                          if (_isCorrected) ...[
                            const SizedBox(height: 16),
                            TextField(
                              controller: _closureRemarkController,
                              maxLines: 2,
                              decoration: InputDecoration(
                                labelText: 'Closure Remark *',
                                hintText: 'How was this issue resolved?',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                fillColor: isDark ? Colors.black26 : const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.all(14),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                if (_closurePhotoPath != null)
                                  GestureDetector(
                                    onTap: () => _showFullImage(_closurePhotoPath!),
                                    child: Container(
                                      margin: const EdgeInsets.only(right: 12),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.green),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(7),
                                        child: (kIsWeb || _closurePhotoPath!.startsWith('http'))
                                            ? Image.network(_closurePhotoPath!, width: 70, height: 70, fit: BoxFit.cover)
                                            : Image.file(File(_closurePhotoPath!), width: 70, height: 70, fit: BoxFit.cover),
                                      ),
                                    ),
                                  ),
                                ElevatedButton.icon(
                                  onPressed: () => _capturePhoto(isClosure: true),
                                  icon: const Icon(Icons.camera_alt, size: 16),
                                  label: Text(_closurePhotoPath == null ? 'Attach Proof Photo *' : 'Retake Proof Photo'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green.shade700,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),

      // Bottom Bar
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 52,
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
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1), width: 1),
      ),
      padding: const EdgeInsets.all(16.0),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: compact ? 8 : 12),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: isDark ? 0.08 : 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: compact ? 16 : 18,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: compact ? 12 : 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'Outfit',
                color: isSelected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
