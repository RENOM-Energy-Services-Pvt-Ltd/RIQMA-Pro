import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../providers/app_settings_provider.dart';
import '../providers/theme_provider.dart';
import '../services/app_update_service.dart';
import '../services/audit_manager.dart';
import '../widgets/update_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersion = 'Loading...';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = 'v${packageInfo.version}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _appVersion = 'Unknown';
        });
      }
    }
  }

  Future<void> _showClearDataDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => const _PendingChecklistsDialog(),
    );
  }

  bool _isCheckingUpdate = false;

  Future<void> _checkForUpdate() async {
    if (_isCheckingUpdate) return;
    setState(() => _isCheckingUpdate = true);
    try {
      final info = await AppUpdateService.instance.checkForUpdate();
      if (!mounted) return;

      if (info != null && info.hasUpdate && info.apkUrl.isNotEmpty) {
        await UpdateDialog.show(context, info);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('App is up to date ($_appVersion)'),
            backgroundColor: const Color(0xFF00897B),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to check for updates: $e'),
            backgroundColor: Colors.red[800],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final appSettings = Provider.of<AppSettingsProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Appearance', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          ),
          SwitchListTile(
            title: const Text('Dark Mode'),
            value: themeProvider.isDarkMode,
            onChanged: (value) {
              themeProvider.toggleTheme(value);
            },
            secondary: Icon(
              themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Audit Workflow', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          ),
          SwitchListTile(
            title: const Text('Restrict Navigation'),
            subtitle: const Text('Require full details for "Not OK" tasks before moving next'),
            value: appSettings.restrictNavWithoutDetails,
            onChanged: (value) {
              appSettings.setRestrictNavWithoutDetails(value);
            },
            secondary: const Icon(Icons.block_flipped),
          ),
          SwitchListTile(
            title: const Text('Mandatory Observation'),
            subtitle: const Text('Make observation text required in task screen'),
            value: appSettings.mandatoryObservationText,
            onChanged: (value) {
              appSettings.setMandatoryObservationText(value);
            },
            secondary: const Icon(Icons.edit_note),
          ),
          SwitchListTile(
            title: const Text('Allow Gallery Photo Import'),
            subtitle: const Text('Allow importing photos from gallery in task screen'),
            value: appSettings.allowGalleryImport,
            onChanged: (value) {
              appSettings.setAllowGalleryImport(value);
            },
            secondary: const Icon(Icons.photo_library_outlined),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Data Management', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Clear Incomplete Data', style: TextStyle(color: Colors.red)),
            subtitle: const Text('Delete pending/incomplete audit drafts from local storage'),
            onTap: _showClearDataDialog,
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('About', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('App Version'),
            trailing: Text(
              _appVersion,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.system_update_rounded, color: Color(0xFF00897B)),
            title: const Text('Check for Updates'),
            subtitle: const Text('Find and install latest version directly'),
            trailing: _isCheckingUpdate
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _isCheckingUpdate ? null : _checkForUpdate,
          ),
        ],
      ),
    );
  }
}

class _PendingChecklistsDialog extends StatefulWidget {
  const _PendingChecklistsDialog();

  @override
  State<_PendingChecklistsDialog> createState() => _PendingChecklistsDialogState();
}

class _PendingChecklistsDialogState extends State<_PendingChecklistsDialog> {
  bool _isLoading = true;
  List<DraftAuditSummary> _drafts = [];

  @override
  void initState() {
    super.initState();
    _loadDrafts();
  }

  Future<void> _loadDrafts() async {
    setState(() => _isLoading = true);
    try {
      final list = await AuditManager.instance.getAllIncompleteAudits();
      if (mounted) {
        setState(() {
          _drafts = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading incomplete audits: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteSingleDraft(DraftAuditSummary draft, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 28),
            const SizedBox(width: 8),
            const Text('Delete Checklist?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete incomplete audit for "${draft.turbineName}"?',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('. ${draft.totalTasksAnswered} answered tasks will be lost', style: TextStyle(color: Colors.red.shade900, fontSize: 13)),
                  if (draft.photoCount > 0)
                    Text('. ${draft.photoCount} locally stored photos will be deleted', style: TextStyle(color: Colors.red.shade900, fontSize: 13)),
                  if (draft.observationCount > 0)
                    Text('. ${draft.observationCount} recorded observations will be deleted', style: TextStyle(color: Colors.red.shade900, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This action cannot be undone.',
              style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await AuditManager.instance.deleteDraft(draft.draftId);
        setState(() {
          _drafts.removeAt(index);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted pending audit for ${draft.turbineName}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting audit: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _deleteAllDrafts() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: Colors.red.shade700, size: 28),
            const SizedBox(width: 8),
            const Text('Delete All Audits?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete all ${_drafts.length} incomplete checklists? All recorded answers and local photos will be permanently cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE ALL'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        for (var draft in List<DraftAuditSummary>.from(_drafts)) {
          await AuditManager.instance.deleteDraft(draft.draftId);
        }
        setState(() {
          _drafts.clear();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All incomplete audits have been cleared.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting audits: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Widget _buildStatBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.pending_actions_rounded, color: Colors.amber.shade900, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pending Checklists',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isLoading
                              ? 'Scanning storage...'
                              : '${_drafts.length} incomplete ${_drafts.length == 1 ? 'checklist' : 'checklists'} found',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Body
            Flexible(
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text(
                            'Scanning device storage for incomplete checklists...',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : _drafts.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.check_circle_outline_rounded, color: Colors.green.shade600, size: 48),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No Incomplete Data Found',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'All audit checklists are clean. There are no pending drafts stored on this device.',
                                style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          shrinkWrap: true,
                          itemCount: _drafts.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final draft = _drafts[index];
                            final formattedDate = draft.lastSaved != null
                                ? DateFormat('dd MMM yyyy, hh:mm a').format(draft.lastSaved!)
                                : 'Unknown Time';

                            return Container(
                              decoration: BoxDecoration(
                                color: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                                ),
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Card Header: Turbine Name, Plan Badge, Delete Button
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    draft.turbineName,
                                                    style: const TextStyle(
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: draft.isUnplanned
                                                        ? Colors.orange.withValues(alpha: 0.15)
                                                        : const Color(0xFF00897B).withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    draft.isUnplanned ? 'Unplanned' : 'Planned',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w600,
                                                      color: draft.isUnplanned
                                                          ? Colors.orange.shade800
                                                          : const Color(0xFF00897B),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            // Site and State
                                            Row(
                                              children: [
                                                Icon(Icons.location_on_outlined, size: 13, color: Colors.grey.shade600),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    '${draft.siteName}${draft.stateName.isNotEmpty ? ' . ${draft.stateName}' : ''}',
                                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Individual Delete Button
                                      IconButton(
                                        icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade600),
                                        onPressed: () => _deleteSingleDraft(draft, index),
                                        tooltip: 'Delete this checklist',
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 8),

                                  // Last Saved Timestamp
                                  Row(
                                    children: [
                                      Icon(Icons.access_time_rounded, size: 13, color: Colors.blueGrey.shade600),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Last saved: $formattedDate',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.blueGrey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 10),

                                  // Filled Data Stats Chips
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      _buildStatBadge(
                                        Icons.checklist_rounded,
                                        '${draft.totalTasksAnswered} Answered',
                                        Colors.blueGrey.shade700,
                                      ),
                                      if (draft.photoCount > 0)
                                        _buildStatBadge(
                                          Icons.photo_camera_outlined,
                                          '${draft.photoCount} Photos',
                                          Colors.indigo.shade600,
                                        ),
                                      if (draft.observationCount > 0)
                                        _buildStatBadge(
                                          Icons.edit_note_rounded,
                                          '${draft.observationCount} Observations',
                                          Colors.amber.shade900,
                                        ),
                                      if (draft.okCount > 0)
                                        _buildStatBadge(
                                          Icons.check_circle_outline,
                                          '${draft.okCount} OK',
                                          Colors.green.shade700,
                                        ),
                                      if (draft.notOkCount > 0)
                                        _buildStatBadge(
                                          Icons.cancel_outlined,
                                          '${draft.notOkCount} Not OK',
                                          Colors.red.shade700,
                                        ),
                                      if (draft.naCount > 0)
                                        _buildStatBadge(
                                          Icons.remove_circle_outline,
                                          '${draft.naCount} N/A',
                                          Colors.grey.shade600,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),

            // Actions Footer
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  if (_drafts.length > 1)
                    TextButton.icon(
                      onPressed: _deleteAllDrafts,
                      icon: const Icon(Icons.delete_sweep_outlined, color: Colors.red, size: 18),
                      label: Text(
                        'DELETE ALL (${_drafts.length})',
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('CLOSE'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
