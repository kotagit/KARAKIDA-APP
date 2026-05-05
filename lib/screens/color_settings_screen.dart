import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../providers/sheets_provider.dart';

class ColorSettingsScreen extends StatefulWidget {
  const ColorSettingsScreen({super.key});

  @override
  State<ColorSettingsScreen> createState() => _ColorSettingsScreenState();
}

class _ColorSettingsScreenState extends State<ColorSettingsScreen> {
  late Color _primary;
  late Color _accent;
  late Color _text;
  bool _saving = false;

  static const _primaryPresets = [
    Color(0xFF047CBC),
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFAD1457),
    Color(0xFFE65100),
    Color(0xFF37474F),
    Color(0xFF000000),
  ];

  static const _accentPresets = [
    Color(0xFFF1C232),
    Color(0xFFFF6F00),
    Color(0xFFF44336),
    Color(0xFF4CAF50),
    Color(0xFF00BCD4),
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFF607D8B),
  ];

  static const _textPresets = [
    Color(0xFF047CBC),
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFAD1457),
    Color(0xFFE65100),
    Color(0xFF37474F),
    Color(0xFF000000),
  ];

  @override
  void initState() {
    super.initState();
    final tp = context.read<ThemeProvider>();
    _primary = tp.primaryColor;
    _accent = tp.accentColor;
    _text = tp.textColor;
  }

  Future<void> _save() async {
    final email = context.read<SheetsProvider>().currentUserEmail;
    if (email == null) return;
    setState(() => _saving = true);
    await context.read<ThemeProvider>().saveSettings(
      email: email,
      primaryColor: _primary,
      accentColor: _accent,
      textColor: _text,
    );
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存しました')),
      );
    }
  }

  void _reset() {
    setState(() {
      _primary = const Color(0xFF047CBC);
      _accent = const Color(0xFFF1C232);
      _text = const Color(0xFF047CBC);
    });
    context.read<ThemeProvider>().saveSettings(
      email: context.read<SheetsProvider>().currentUserEmail ?? '',
      primaryColor: _primary,
      accentColor: _accent,
      textColor: _text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('カラー設定', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
            onPressed: _reset,
            child: const Text('リセット', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection(
              context,
              label: 'メインカラー',
              description: 'AppBar・ボタン・ボーダーの色',
              selected: _primary,
              presets: _primaryPresets,
              onSelected: (c) {
                setState(() => _primary = c);
                context.read<ThemeProvider>().saveSettings(
                  email: context.read<SheetsProvider>().currentUserEmail ?? '',
                  primaryColor: c,
                  accentColor: _accent,
                  textColor: _text,
                );
              },
            ),
            const SizedBox(height: 24),
            _buildSection(
              context,
              label: 'アクセントカラー',
              description: '地図アイコン・ハイライトの色',
              selected: _accent,
              presets: _accentPresets,
              onSelected: (c) {
                setState(() => _accent = c);
                context.read<ThemeProvider>().saveSettings(
                  email: context.read<SheetsProvider>().currentUserEmail ?? '',
                  primaryColor: _primary,
                  accentColor: c,
                  textColor: _text,
                );
              },
            ),
            const SizedBox(height: 24),
            _buildSection(
              context,
              label: 'テキストカラー',
              description: 'セクション見出し・ラベルテキストの色',
              selected: _text,
              presets: _textPresets,
              onSelected: (c) {
                setState(() => _text = c);
                context.read<ThemeProvider>().saveSettings(
                  email: context.read<SheetsProvider>().currentUserEmail ?? '',
                  primaryColor: _primary,
                  accentColor: _accent,
                  textColor: c,
                );
              },
            ),
            const SizedBox(height: 32),
            _buildPreview(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String label,
    required String description,
    required Color selected,
    required List<Color> presets,
    required ValueChanged<Color> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(description, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: presets.map((color) {
            final isSelected = color.value == selected.value;
            return GestureDetector(
              onTap: () => onSelected(color),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.black : Colors.grey.shade300,
                    width: isSelected ? 3 : 1,
                  ),
                  boxShadow: isSelected
                      ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8)]
                      : null,
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPreview(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('プレビュー', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _primary,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: const Text('AppBar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      color: _primary.withOpacity(0.15),
                      child: Text('セクション見出し', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _text)),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(Icons.location_on, color: _accent, size: 20),
                      const SizedBox(width: 4),
                      const Text('住所テキスト（太字）', style: TextStyle(fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('ボタン', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
