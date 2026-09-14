import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AuditDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> auditData;
  final String siteName;
  final String turbineName;
  final Timestamp? timestamp;

  const AuditDetailsScreen({
    required this.auditData, required this.siteName, required this.turbineName, super.key,
    this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    final allTasks = auditData.entries.toList();
    // Filter for only NCs (Not OK items)
    final ncTasks = allTasks.where((entry) {
      final data = entry.value as Map<String, dynamic>;
      return data['status'] == 'Not OK';
    }).toList();

    final dateStr = timestamp != null
        ? DateFormat('dd MMM yyyy, hh:mm a').format(timestamp!.toDate())
        : 'Unknown Date';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$siteName - $turbineName',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              dateStr,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ncTasks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade400),
                  const SizedBox(height: 16),
                  const Text('No Non-Conformances', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Text('This turbine is 100% compliant.', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : Column(
              children: [
                // Summary bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  color: Theme.of(context).brightness == Brightness.dark 
                      ? Colors.red.withValues(alpha: 0.2) 
                      : Colors.red.shade50,
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        'Found ${ncTasks.length} Non-Conformances',
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: ncTasks.length,
                    itemBuilder: (context, index) {
                      final taskData = ncTasks[index].value as Map<String, dynamic>;
                      return _buildTaskCard(context, taskData);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildTaskCard(BuildContext context, Map<String, dynamic> taskData) {
    final question = (taskData['question'] as String?) ?? 'Unknown Question';
    final status = (taskData['status'] as String?) ?? 'Unknown';
    final remarks = (taskData['remarks'] as String?) ?? '';
    final observation = (taskData['observation'] as String?) ?? '';
    final photos = (taskData['photos'] as List<dynamic>?) ?? [];
    final subCategory = (taskData['sub_category_name'] as String?) ?? '';
    
    // Manager Feedback Fields
    final adminStatus = taskData['admin_status'] as String?;
    final adminRemarks = taskData['admin_remarks'] as String?;

    Color statusColor = Colors.grey;
    if (status == 'OK') statusColor = Colors.green;
    if (status == 'Not OK') statusColor = Colors.red;

    final isCorrection = adminStatus == 'Correction';
    final isApproved = adminStatus == 'Approved';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCorrection
            ? const BorderSide(color: Colors.red, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Question and Status
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        question,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      // Show Sub-Category instead of Reference
                      if (subCategory.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Row(
                            children: [
                              Icon(
                                Icons.folder_outlined,
                                size: 14,
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                subCategory,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            
            // Auditor Observation
            if (observation.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Auditor Observation:',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Text(observation),
            ],

            // Auditor Remarks
            if (remarks.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Auditor Remarks:',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Text(remarks),
            ],

            // Photos with Tap to Zoom
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: photos.length,
                  itemBuilder: (context, index) {
                    final photoUrl = photos[index] as String;
                    return GestureDetector(
                      onTap: () => _showPhotoViewer(context, photos.cast<String>(), index),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: 80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                photoUrl,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      value: loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress.cumulativeBytesLoaded /
                                              loadingProgress.expectedTotalBytes!
                                          : null,
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.grey[200],
                                    child: const Icon(Icons.broken_image, color: Colors.grey),
                                  );
                                },
                              ),
                              // Zoom icon overlay
                              Positioned(
                                bottom: 4,
                                right: 4,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Icon(
                                    Icons.zoom_in,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],

            // Manager Feedback Section
            if (adminStatus != null) ...[
              const Divider(height: 24),
              Row(
                children: [
                  Icon(
                    isApproved ? Icons.check_circle : Icons.warning_amber_rounded,
                    color: isApproved ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Manager Review: $adminStatus',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isApproved ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
              if (isCorrection && adminRemarks != null && adminRemarks.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    adminRemarks,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ],

            // On-the-Spot Correction Details
            if (taskData['is_corrected'] == true) ...[
              const Divider(height: 24),
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'On-the-Spot Correction',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green),
                    ),
                    child: const Text(
                      'RESOLVED',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Correction Remark:',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Text(
                (taskData['closure_remark'] as String?) ?? 'No remark provided.',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              if (taskData['closure_photo'] != null) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => _showPhotoViewer(context, [taskData['closure_photo'] as String], 0),
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        taskData['closure_photo'] as String,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _showPhotoViewer(BuildContext context, List<String> photos, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => PhotoViewerScreen(
          photos: photos,
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}

// Full-screen Photo Viewer with Zoom
class PhotoViewerScreen extends StatefulWidget {
  final List<String> photos;
  final int initialIndex;

  const PhotoViewerScreen({
    required this.photos,
    required this.initialIndex,
    super.key,
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          'Photo ${_currentIndex + 1} of ${widget.photos.length}',
          style: const TextStyle(fontSize: 16),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.photos.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: Image.network(
                widget.photos[index],
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.broken_image, color: Colors.white54, size: 64),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load image',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: widget.photos.length > 1
          ? Container(
              padding: const EdgeInsets.all(16),
              color: Colors.black,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.photos.length,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentIndex == index ? Colors.white : Colors.grey,
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
