import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

class ThemeProvider extends ChangeNotifier {
  Color _primaryColor = const Color(0xFF047CBC);
  Color _accentColor = const Color(0xFFF1C232);
  Color _textColor = const Color(0xFF047CBC);

  Color get primaryColor => _primaryColor;
  Color get accentColor => _accentColor;
  Color get textColor => _textColor;

  Future<void> loadSettings(String email) async {
    try {
      final settings = await FirestoreService.getUserSettings(email);
      if (settings != null) {
        if (settings['primaryColor'] != null) {
          _primaryColor = _hexToColor(settings['primaryColor'] as String);
        }
        if (settings['accentColor'] != null) {
          _accentColor = _hexToColor(settings['accentColor'] as String);
        }
        if (settings['textColor'] != null) {
          _textColor = _hexToColor(settings['textColor'] as String);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('ThemeProvider.loadSettings error: $e');
    }
  }

  Future<void> saveSettings({
    required String email,
    Color? primaryColor,
    Color? accentColor,
    Color? textColor,
  }) async {
    if (primaryColor != null) _primaryColor = primaryColor;
    if (accentColor != null) _accentColor = accentColor;
    if (textColor != null) _textColor = textColor;
    notifyListeners();
    try {
      await FirestoreService.saveUserSettings(
        email: email,
        primaryColor: _colorToHex(_primaryColor),
        accentColor: _colorToHex(_accentColor),
        textColor: _colorToHex(_textColor),
      );
    } catch (e) {
      debugPrint('ThemeProvider.saveSettings error: $e');
    }
  }

  Color _hexToColor(String hex) {
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length == 6) {
      return Color(int.parse('FF$cleaned', radix: 16));
    }
    return const Color(0xFF047CBC);
  }

  String _colorToHex(Color color) {
    return color.value.toRadixString(16).substring(2).toUpperCase();
  }
}
