import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Singleton service for logging user activities to Firestore.
/// Syncs with Web Dashboard's activity_logs collection.
class ActivityLogService {
  ActivityLogService._();
  static final ActivityLogService instance = ActivityLogService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _appVersion;

  /// Initialize the service with app version info
  Future<void> init() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = packageInfo.version;
    } catch (e) {
      _appVersion = 'unknown';
      debugPrint('ActivityLogService: Failed to get package info: $e');
    }
  }

  /// Log an activity event to Firestore.
  /// 
  /// [actionType] - Type of action (LOGIN, LOGOUT, AUDIT_START, AUDIT_SUBMIT, AUDIT_PLAN_ADD)
  /// [description] - Human-readable description of the action
  /// [metadata] - Additional context data (turbineId, siteId, etc.)
  Future<void> logActivity({
    required String actionType,
    required String description,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('ActivityLogService: No authenticated user, skipping log');
        return;
      }

      // Fetch user details from Firestore
      var userName = user.displayName ?? user.email?.split('@')[0] ?? 'Unknown';
      var userRole = 'Auditor';
      
      try {
        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          userName = (userData['name'] as String?) ?? userName;
          userRole = (userData['role'] as String?) ?? userRole;
        }
      } catch (e) {
        debugPrint('ActivityLogService: Failed to fetch user details: $e');
      }

      // Generate unique log ID
      final logId = _firestore.collection('activity_logs').doc().id;

      // Build metadata with platform info
      final enrichedMetadata = <String, dynamic>{
        'platform': 'mobile',
        'appVersion': _appVersion ?? 'unknown',
        ...?metadata,
      };

      // Create log entry (fire-and-forget, Firestore handles offline queuing)
      await _firestore.collection('activity_logs').doc(logId).set({
        'logId': logId,
        'actionType': actionType,
        'description': description,
        'userId': user.uid,
        'userName': userName,
        'userRole': userRole,
        'timestamp': FieldValue.serverTimestamp(),
        'metadata': enrichedMetadata,
      });

      debugPrint('ActivityLogService: Logged $actionType - $description');
    } catch (e) {
      // Don't throw, just log the error - logging shouldn't break the app flow
      debugPrint('ActivityLogService: Failed to log activity: $e');
    }
  }
}
