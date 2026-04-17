import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../providers/app_settings_provider.dart';
import '../providers/theme_provider.dart';
import '../services/audit_manager.dart';

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
    final drafts = await AuditManager.instance.getAllDraftsMetadata();
    
    if (!mounted) return;

    if (drafts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No incomplete checklist data found.')),
      );
      return;
    }

    // Step 1: General Confirmation
    final confirmFirst = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Incomplete Data?'),
        content: const Text('This will delete all saved drafts that haven\'t been submitted yet. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('PROCEED', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmFirst != true || !mounted) return;

    // Step 2: Specific Turbine Confirmation
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Confirm Deletion'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('The following pending audits will be deleted:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: drafts.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (itemContext, index) {
                        final draft = drafts[index];
                        final date = draft['timestamp'] != null 
                            ? DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(draft['timestamp'] as String))
                            : 'Unknown Date';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(draft['turbineName']?.toString() ?? 'Unknown Turbine'),
                          subtitle: Text('${draft['siteName']}\n$date', style: const TextStyle(fontSize: 12)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () async {
                              await AuditManager.instance.deleteDraft(draft['draft_id'] as String);
                              setDialogState(() {
                                drafts.removeAt(index);
                              });
                              if (drafts.isEmpty) {
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                }
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('DONE')),
              if (drafts.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    final confirmAll = await showDialog<bool>(
                      context: dialogContext,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete All?'),
                        content: Text('Delete all ${drafts.length} pending audits?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('NO')),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('YES, DELETE ALL')),
                        ],
                      ),
                    );
                    
                    if (confirmAll == true) {
                      for (var draft in drafts) {
                        await AuditManager.instance.deleteDraft(draft['draft_id'] as String);
                      }
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                    }
                  },
                  child: const Text('DELETE ALL', style: TextStyle(color: Colors.red)),
                ),
            ],
          );
        }
      ),
    );
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
        ],
      ),
    );
  }
}
