import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsProvider with ChangeNotifier {
  static const String _keyRestrictNav = 'restrict_nav_without_details';
  static const String _keyMandatoryObs = 'mandatory_observation_text';
  static const String _keyAllowGalleryImport = 'allow_gallery_import';

  bool _restrictNavWithoutDetails = false;
  bool _mandatoryObservationText = false;
  bool _allowGalleryImport = false;

  bool get restrictNavWithoutDetails => _restrictNavWithoutDetails;
  bool get mandatoryObservationText => _mandatoryObservationText;
  bool get allowGalleryImport => _allowGalleryImport;

  AppSettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _restrictNavWithoutDetails = prefs.getBool(_keyRestrictNav) ?? false;
      _mandatoryObservationText = prefs.getBool(_keyMandatoryObs) ?? false;
      _allowGalleryImport = prefs.getBool(_keyAllowGalleryImport) ?? false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading app settings: $e');
    }
  }

  Future<void> setRestrictNavWithoutDetails(bool value) async {
    _restrictNavWithoutDetails = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRestrictNav, value);
  }

  Future<void> setMandatoryObservationText(bool value) async {
    _mandatoryObservationText = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyMandatoryObs, value);
  }

  Future<void> setAllowGalleryImport(bool value) async {
    _allowGalleryImport = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAllowGalleryImport, value);
  }
}
