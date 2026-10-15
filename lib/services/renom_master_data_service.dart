import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'renom_auth_service.dart';

class RenomMasterDataService {
  static final RenomMasterDataService instance = RenomMasterDataService._internal();
  RenomMasterDataService._internal();

  static const String baseUrl = 'https://dev.renomportalapi.renom.in';

  // Cache keys
  static const String _kStatesCache = 'cache_renom_states';
  static const String _kSitesCache = 'cache_renom_sites';
  static const String _kTurbinesCache = 'cache_renom_turbines';
  static const String _kModelsCache = 'cache_renom_models';

  Map<String, String> _getAuthHeaders() {
    final token = RenomAuthService.instance.currentUser?.jwtToken ?? '';
    return {
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// 1. Fetch States (From Renom Server API `/StateMaster`, fallback to cache/Firestore)
  Future<List<Map<String, dynamic>>> getStates({bool forceRefresh = false}) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/StateMaster'), headers: _getAuthHeaders())
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> raw = jsonDecode(response.body) as List<dynamic>;
        final List<Map<String, dynamic>> states = raw.map((item) {
          final m = Map<String, dynamic>.from(item as Map);
          final String docId = (m['docid'] ?? '').toString();
          final String name = (m['statename'] ?? '').toString().trim();
          final String code = (m['statecode'] ?? '').toString().trim();
          return <String, dynamic>{
            'id': docId,
            'state': name,
            'name': name,
            'state_code': code,
            'state_id': docId,
          };
        }).where((s) => (s['name'] as String).isNotEmpty).toList();

        // Sort alphabetically
        states.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

        // Save to cache
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kStatesCache, jsonEncode(states));
        debugPrint('RenomMasterDataService: Loaded ${states.length} states from Renom API');
        return states;
      }
    } catch (e) {
      debugPrint('RenomMasterDataService: States API error ($e), attempting local cache...');
    }

    // Fallback 1: Local Cache
    final cached = await _getCachedList(_kStatesCache);
    if (cached.isNotEmpty) {
      debugPrint('RenomMasterDataService: Returning ${cached.length} states from local cache');
      return cached;
    }

    // Fallback 2: Firestore
    try {
      final snap = await FirebaseFirestore.instance.collection('states').get();
      return snap.docs.map((doc) => {'id': doc.id, 'reference': doc.reference, ...doc.data()}).toList();
    } catch (_) {
      return [];
    }
  }

  /// 2. Fetch Sites (From Renom Server API `/LocationMaster`, fallback to cache/Firestore)
  Future<List<Map<String, dynamic>>> getSites({bool forceRefresh = false}) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/LocationMaster'), headers: _getAuthHeaders())
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> raw = jsonDecode(response.body) as List<dynamic>;
        final List<Map<String, dynamic>> sites = raw.map((item) {
          final m = Map<String, dynamic>.from(item as Map);
          final String docId = (m['docid'] ?? '').toString();
          final String name = (m['locationname'] ?? '').toString().trim();
          final String code = (m['locationcode'] ?? '').toString().trim();
          final String stateId = (m['stateid'] ?? '').toString();
          final String stateName = (m['statename'] ?? '').toString().trim();
          final String address = (m['locaddress'] ?? '').toString().trim();
          final String zone = (m['loczone'] ?? '').toString().trim();

          return <String, dynamic>{
            'id': docId,
            'name': name,
            'site_name': name,
            'site_code': code,
            'state_id': stateId,
            'state_name': stateName,
            'state': stateName,
            'address': address,
            'zone': zone,
          };
        }).where((s) => (s['name'] as String).isNotEmpty).toList();

        sites.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kSitesCache, jsonEncode(sites));
        debugPrint('RenomMasterDataService: Loaded ${sites.length} sites from Renom API');
        return sites;
      }
    } catch (e) {
      debugPrint('RenomMasterDataService: Sites API error ($e), attempting local cache...');
    }

    final cached = await _getCachedList(_kSitesCache);
    if (cached.isNotEmpty) {
      return cached;
    }

    try {
      final snap = await FirebaseFirestore.instance.collection('sites').get();
      return snap.docs.map((doc) => {'id': doc.id, 'reference': doc.reference, ...doc.data()}).toList();
    } catch (_) {
      return [];
    }
  }

  /// 3. Fetch Turbines & Derive Models (From Renom Server API `/TurbineMaster`)
  Future<Map<String, List<Map<String, dynamic>>>> getTurbinesAndModels({bool forceRefresh = false}) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/TurbineMaster'), headers: _getAuthHeaders())
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final List<dynamic> raw = jsonDecode(response.body) as List<dynamic>;

        final List<Map<String, dynamic>> turbines = [];
        final Map<String, Map<String, dynamic>> uniqueModels = {};

        for (final item in raw) {
          final m = Map<String, dynamic>.from(item as Map);
          final String docId = (m['docid'] ?? '').toString();
          final String turbineCode = (m['turbinecode'] ?? '').toString().trim();
          final String serialNo = (m['turbserialno'] ?? '').toString().trim();
          final String make = (m['turbinemake'] ?? '').toString().trim();
          final String model = (m['turbinemodel'] ?? '').toString().trim();
          final String siteName = (m['locationname'] ?? '').toString().trim();
          final String customer = (m['customername'] ?? '').toString().trim();
          final String gps = (m['gpscoords'] ?? '').toString().trim();

          if (turbineCode.isEmpty) continue;

          turbines.add({
            'id': docId,
            'name': turbineCode,
            'turbine_id': turbineCode,
            'serial_no': serialNo,
            'make': make,
            'turbine_make': make,
            'model': model,
            'turbine_model': model,
            'site_name': siteName,
            'site': siteName,
            'customer_name': customer,
            'customer': customer,
            'gps': gps,
          });

          if (model.isNotEmpty && !uniqueModels.containsKey(model)) {
            uniqueModels[model] = {
              'id': model,
              'name': model,
              'model': model,
              'turbine_model': model,
              'make': make,
              'turbine_make': make,
            };
          }
        }

        turbines.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
        final List<Map<String, dynamic>> modelsList = uniqueModels.values.toList();
        modelsList.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

        // Cache both
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kTurbinesCache, jsonEncode(turbines));
        await prefs.setString(_kModelsCache, jsonEncode(modelsList));

        debugPrint('RenomMasterDataService: Loaded ${turbines.length} turbines and ${modelsList.length} models from Renom API');

        return {
          'turbines': turbines,
          'models': modelsList,
        };
      }
    } catch (e) {
      debugPrint('RenomMasterDataService: TurbineMaster API error ($e), attempting local cache...');
    }

    final cachedTurbines = await _getCachedList(_kTurbinesCache);
    final cachedModels = await _getCachedList(_kModelsCache);

    if (cachedTurbines.isNotEmpty && cachedModels.isNotEmpty) {
      return {
        'turbines': cachedTurbines,
        'models': cachedModels,
      };
    }

    // Fallback to Firestore
    try {
      final tSnap = await FirebaseFirestore.instance.collection('turbinename').get();
      final mSnap = await FirebaseFirestore.instance.collection('turbinemodel').get();

      return {
        'turbines': tSnap.docs.map((doc) => {'id': doc.id, 'reference': doc.reference, ...doc.data()}).toList(),
        'models': mSnap.docs.map((doc) => {'id': doc.id, 'reference': doc.reference, ...doc.data()}).toList(),
      };
    } catch (_) {
      return {'turbines': [], 'models': []};
    }
  }

  /// Helper: Load JSON list from local cache
  Future<List<Map<String, dynamic>>> _getCachedList(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(key);
      if (str != null && str.isNotEmpty) {
        final List<dynamic> list = jsonDecode(str) as List<dynamic>;
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('Error reading $key from cache: $e');
    }
    return [];
  }
}
