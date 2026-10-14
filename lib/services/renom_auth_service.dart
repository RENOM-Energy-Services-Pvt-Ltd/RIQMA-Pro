import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class RenomUser {
  final String docId;
  final String name;
  final String username;
  final String email;
  final String role; // 'manager', 'auditor'
  final String rawRole; // 'superadmin', 'admin', 'auditor', etc.
  final String empCode;
  final String department;
  final String designation;
  final String locationId;
  final String locationName;
  final String jwtToken;
  final String assignedState;
  final String teamType;

  RenomUser({
    required this.docId,
    required this.name,
    required this.username,
    required this.email,
    required this.role,
    required this.rawRole,
    required this.empCode,
    required this.department,
    required this.designation,
    required this.locationId,
    required this.locationName,
    required this.jwtToken,
    required this.assignedState,
    required this.teamType,
  });

  bool get isSuperAdmin => rawRole.toLowerCase() == 'superadmin';
  bool get isAdmin => rawRole.toLowerCase() == 'admin';
  bool get isManager => role.toLowerCase() == 'manager';
  bool get isAuditor => role.toLowerCase() == 'auditor';

  Map<String, dynamic> toJson() => {
        'docId': docId,
        'name': name,
        'username': username,
        'email': email,
        'role': role,
        'rawRole': rawRole,
        'empCode': empCode,
        'department': department,
        'designation': designation,
        'locationId': locationId,
        'locationName': locationName,
        'jwtToken': jwtToken,
        'assignedState': assignedState,
        'teamType': teamType,
      };

  factory RenomUser.fromJson(Map<String, dynamic> json) => RenomUser(
        docId: json['docId']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        role: json['role']?.toString() ?? 'auditor',
        rawRole: json['rawRole']?.toString() ?? json['role']?.toString() ?? 'auditor',
        empCode: json['empCode']?.toString() ?? '',
        department: json['department']?.toString() ?? '',
        designation: json['designation']?.toString() ?? '',
        locationId: json['locationId']?.toString() ?? '',
        locationName: json['locationName']?.toString() ?? '',
        jwtToken: json['jwtToken']?.toString() ?? '',
        assignedState: json['assignedState']?.toString() ?? 'All',
        teamType: json['teamType']?.toString() ?? 'auditor',
      );
}

class RenomAuthService {
  static final RenomAuthService instance = RenomAuthService._internal();
  RenomAuthService._internal();

  static const String baseUrl = 'https://dev.renomportalapi.renom.in';
  static const String _userPrefKey = 'renom_mobile_current_user';

  RenomUser? _currentUser;
  RenomUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null && _currentUser!.jwtToken.isNotEmpty;

  final ValueNotifier<RenomUser?> userNotifier = ValueNotifier<RenomUser?>(null);

  /// Load cached user session from SharedPreferences
  Future<RenomUser?> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_userPrefKey);
      if (userJson != null && userJson.isNotEmpty) {
        final Map<String, dynamic> map =
            Map<String, dynamic>.from(jsonDecode(userJson) as Map);
        _currentUser = RenomUser.fromJson(map);
        userNotifier.value = _currentUser;

        // Maintain anonymous Firebase Auth during transition so remaining Firestore queries don't fail
        if (FirebaseAuth.instance.currentUser == null) {
          try {
            await FirebaseAuth.instance.signInAnonymously();
            debugPrint('RenomAuthService: Anonymously signed into Firebase for transitional queries');
          } catch (e) {
            debugPrint('RenomAuthService: Anonymous Firebase Auth notice: $e');
          }
        }

        // Verify if Firestore users collection has a specific assigned_state
        try {
          final querySnap = await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: _currentUser!.email)
              .limit(1)
              .get();
          if (querySnap.docs.isNotEmpty) {
            final fData = querySnap.docs.first.data();
            final fState = fData['assigned_state']?.toString().trim();
            if (fState != null && fState.isNotEmpty && fState.toLowerCase() != 'all' && fState != _currentUser!.assignedState) {
              final updated = RenomUser(
                docId: _currentUser!.docId,
                name: _currentUser!.name,
                username: _currentUser!.username,
                email: _currentUser!.email,
                role: _currentUser!.role,
                rawRole: _currentUser!.rawRole,
                empCode: _currentUser!.empCode,
                department: _currentUser!.department,
                designation: _currentUser!.designation,
                locationId: _currentUser!.locationId,
                locationName: _currentUser!.locationName,
                jwtToken: _currentUser!.jwtToken,
                assignedState: fState,
                teamType: _currentUser!.teamType,
              );
              _currentUser = updated;
              userNotifier.value = updated;
              await prefs.setString(_userPrefKey, jsonEncode(updated.toJson()));
            }
          }
        } catch (_) {}

        return _currentUser;
      }
    } catch (e) {
      debugPrint('Error loading saved Renom user session: $e');
    }
    return null;
  }

  /// Authenticate against Renom Server API
  Future<RenomUser> login({
    required String username,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/UserAccount/authenticate');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username.trim(),
        'password': password.trim(),
      }),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data =
          Map<String, dynamic>.from(jsonDecode(response.body) as Map);

      final String docId = data['_DocId']?.toString() ?? '';
      final String firstName = (data['_fristname']?.toString() ?? '').trim();
      final String lastName = (data['_lastname']?.toString() ?? '').trim();
      final String fullName = ('$firstName $lastName').trim().isNotEmpty
          ? ('$firstName $lastName').trim()
          : (data['_username']?.toString() ?? username);

      final String email = data['_mailid']?.toString() ?? '';
      final String roleName = (data['_rolename']?.toString() ?? 'auditor').toLowerCase();
      final String token = data['jwtToken']?.toString() ?? '';
      final String empCode = data['_empcode']?.toString() ?? '';
      final String dept = data['_deptname']?.toString() ?? '';
      final String desig = data['_desgination']?.toString() ?? '';
      final String locId = data['_locationid']?.toString() ?? '';
      final String locName = data['_locationname']?.toString() ?? '';

      final String apiState = (data['_statename'] ??
              data['statename'] ??
              data['_state'] ??
              data['state'] ??
              data['_state_name'] ??
              '')
          .toString()
          .trim();

      String assignedState = apiState.isNotEmpty
          ? apiState
          : (locName.isNotEmpty ? locName : 'All');

      // Check Firestore users collection to see if user has an assigned_state configured
      try {
        final userSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (userSnap.docs.isNotEmpty) {
          final fState = userSnap.docs.first.data()['assigned_state']?.toString().trim();
          if (fState != null && fState.isNotEmpty && fState.toLowerCase() != 'all') {
            assignedState = fState;
          }
        }
      } catch (_) {}

      // Normalize role for RIQMA app
      String normalizedRole = 'auditor';
      if (roleName == 'superadmin' || roleName == 'admin' || roleName == 'manager') {
        normalizedRole = 'manager';
      } else {
        normalizedRole = 'auditor';
      }

      final user = RenomUser(
        docId: docId,
        name: fullName,
        username: data['_username']?.toString() ?? username,
        email: email,
        role: normalizedRole,
        rawRole: roleName,
        empCode: empCode,
        department: dept,
        designation: desig,
        locationId: locId,
        locationName: locName,
        jwtToken: token,
        assignedState: assignedState,
        teamType: 'auditor',
      );

      _currentUser = user;
      userNotifier.value = user;

      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userPrefKey, jsonEncode(user.toJson()));

      // Maintain anonymous Firebase Auth during transition
      if (FirebaseAuth.instance.currentUser == null) {
        try {
          await FirebaseAuth.instance.signInAnonymously();
        } catch (_) {}
      }

      return user;
    } else if (response.statusCode == 401) {
      throw Exception('Invalid Username or Password.');
    } else if (response.statusCode == 429) {
      throw Exception('Too many failed attempts. Account temporarily locked. Please try after some time.');
    } else {
      throw Exception('Server error (${response.statusCode}): ${response.body}');
    }
  }

  /// Logout and clear session
  Future<void> logout() async {
    try {
      if (_currentUser?.jwtToken != null) {
        await http.post(
          Uri.parse('$baseUrl/UserAccount/logout'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${_currentUser!.jwtToken}',
          },
        );
      }
    } catch (_) {}

    _currentUser = null;
    userNotifier.value = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userPrefKey);

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }
}
