import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'screens/activity_log_screen.dart';
import 'screens/reports/auditor_reports_screen.dart';
import 'screens/settings_screen.dart';
import 'services/activity_log_service.dart';
import 'services/app_update_service.dart';
import 'services/audit_manager.dart';
import 'services/renom_auth_service.dart';
import 'services/sync_service.dart';
import 'widgets/update_dialog.dart';
import 'tabs/audit_tab.dart';
import 'tabs/home_tab.dart';
import 'tabs/planning_tab.dart';
import 'widgets/flipkart_bottom_nav_bar.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  String? _assignedState;
  String? _userName;
  String? _userRole;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Clear any stale audit session when returning to dashboard
    // This prevents cross-contamination between audits
    AuditManager.instance.clearSession();
    _loadUserName();
    _checkForStartupUpdate();
  }

  Future<void> _checkForStartupUpdate() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    try {
      final info = await AppUpdateService.instance.checkForUpdate();
      if (mounted && info != null && info.hasUpdate && info.apkUrl.isNotEmpty) {
        await UpdateDialog.show(context, info);
      }
    } catch (e) {
      debugPrint('Dashboard: Startup update check error: $e');
    }
  }

  Future<void> _loadUserName() async {
    final renomUser = RenomAuthService.instance.currentUser;
    if (renomUser != null) {
      String? assignedState;
      if (renomUser.assignedState.isNotEmpty &&
          renomUser.assignedState.toLowerCase() != 'all') {
        assignedState = renomUser.assignedState;
      }

      // Check Firestore users collection to see if user has a specific assigned_state
      try {
        QuerySnapshot userSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: renomUser.email)
            .limit(1)
            .get();
        if (userSnap.docs.isEmpty && renomUser.username.isNotEmpty) {
          userSnap = await FirebaseFirestore.instance
              .collection('users')
              .where('username', isEqualTo: renomUser.username)
              .limit(1)
              .get();
        }
        if (userSnap.docs.isNotEmpty) {
          final fData = userSnap.docs.first.data() as Map<String, dynamic>;
          final fState = fData['assigned_state']?.toString().trim();
          if (fState != null && fState.isNotEmpty && fState.toLowerCase() != 'all') {
            assignedState = fState;
          }
        }
      } catch (e) {
        debugPrint('Error checking firestore for user state: $e');
      }

      if (mounted) {
        setState(() {
          _userRole = renomUser.role;
          _assignedState = assignedState;
          _userName = renomUser.name;
          _isLoading = false;
        });
      }
      SyncService.instance.startSync();
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        // Fetch user document from Firestore
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>;
          setState(() {
            // Check for manager role to allow full access
            _userRole = data['role'] as String?;
            if (_userRole == 'manager') {
              _assignedState = null; // Manager sees data from all states
            } else {
              _assignedState = data['assigned_state'] as String?;
            }

            if (data.containsKey('name')) {
              _userName = data['name'] as String?;
            }
          });

          // Start Offline Sync after profile is ready
          SyncService.instance.startSync();
        }
      } catch (e) {
        debugPrint('Error fetching user profile: $e');
      }
    }
    
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }



  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _showLogoutConfirmation(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      // Log logout event before signing out
      await ActivityLogService.instance.logActivity(
        actionType: 'LOGOUT',
        description: 'User ${_userName ?? 'Unknown'} logged out',
      );
      await RenomAuthService.instance.logout();
      // Navigation is handled by ValueListenableBuilder in main.dart
    }
  }

  String _getDisplayName() {
    final renomUser = RenomAuthService.instance.currentUser;
    if (renomUser != null && renomUser.name.isNotEmpty) {
      return renomUser.name;
    }
    if (_userName != null && _userName!.isNotEmpty) {
      return _userName!;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user?.displayName != null && user!.displayName!.isNotEmpty) {
      return user.displayName!;
    }
    return user?.email?.split('@')[0] ?? 'Auditor';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Use mobile home button to exit.'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Scaffold(
      appBar: AppBar(
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
            ? const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
              )
            : const SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
              ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/images/renom_logo.svg',
              height: 30,
              semanticsLabel: 'Renom Home',
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                _getDisplayName(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (context) => const ActivityLogScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _showLogoutConfirmation(context),
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: FlipkartBottomNavBar(
            currentIndex: _selectedIndex,
            onTap: _onItemTapped,
            items: const [
              FlipkartNavItem(
                icon: Icons.dashboard_outlined,
                activeIcon: Icons.dashboard_rounded,
                label: 'Dashboard',
              ),
              FlipkartNavItem(
                icon: Icons.verified_user_outlined,
                activeIcon: Icons.verified_user_rounded,
                label: 'Audit',
              ),
              FlipkartNavItem(
                icon: Icons.bar_chart_outlined,
                activeIcon: Icons.bar_chart_rounded,
                label: 'Statistics',
              ),
              FlipkartNavItem(
                icon: Icons.calendar_month_outlined,
                activeIcon: Icons.calendar_month_rounded,
                label: 'Planning',
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (_selectedIndex) {
      case 0:
        return HomeTab(assignedState: _assignedState);
      case 1:
        return AuditTab(assignedState: _assignedState);
      case 2:
        return AuditorReportsScreen(isManager: _userRole == 'manager');
      case 3:
        return PlanningTab(assignedState: _assignedState);
      default:
        return const Center(child: Text('Coming Soon'));
    }
  }
}
