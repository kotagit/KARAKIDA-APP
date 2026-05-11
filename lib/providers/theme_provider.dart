import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

class ThemeProvider extends ChangeNotifier {
  Color _primaryColor = const Color(0xFF047CBC);
  Color _accentColor = const Color(0xFFF1C232);
  Color _textColor = const Color(0xFF047CBC);
  Color? _logoColor;
  Color? _logoColorOnDark;

  Color get primaryColor => _primaryColor;
  Color get accentColor => _accentColor;
  Color get textColor => _textColor;
  Color get logoColor => _logoColor ?? _primaryColor;
  // 有色背景用ロゴ。未設定時は白にフォールバック
  Color get logoColorOnDark => _logoColorOnDark ?? Colors.white;

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
        if (settings['logoColor'] != null) {
          _logoColor = _hexToColor(settings['logoColor'] as String);
        }
        if (settings['logoColorOnDark'] != null) {
          _logoColorOnDark = _hexToColor(settings['logoColorOnDark'] as String);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('ThemeProvider.loadSettings error: $e');
    }
  }

  // メモリのみ更新（Firestore書き込みなし）
  void updateColors({Color? primaryColor, Color? accentColor, Color? textColor, Color? logoColor, Color? logoColorOnDark}) {
    if (primaryColor != null) _primaryColor = primaryColor;
    if (accentColor != null) _accentColor = accentColor;
    if (textColor != null) _textColor = textColor;
    if (logoColor != null) _logoColor = logoColor;
    if (logoColorOnDark != null) _logoColorOnDark = logoColorOnDark;
    notifyListeners();
  }

  // Firestoreに保存
  Future<void> saveSettings({required String email}) async {
    await FirestoreService.saveUserSettings(
      email: email,
      primaryColor: _colorToHex(_primaryColor),
      accentColor: _colorToHex(_accentColor),
      textColor: _colorToHex(_textColor),
      logoColor: _colorToHex(logoColor),
      logoColorOnDark: _colorToHex(logoColorOnDark),
    );
  }

  Color _hexToColor(String hex) {
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length == 6) {
      return Color(int.parse('FF$cleaned', radix: 16));
    }
    return const Color(0xFF047CBC);
  }

  String _colorToHex(Color color) {
    final r = color.red.toRadixString(16).padLeft(2, '0');
    final g = color.green.toRadixString(16).padLeft(2, '0');
    final b = color.blue.toRadixString(16).padLeft(2, '0');
    return '$r$g$b'.toUpperCase();
  }
}
