import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
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
  late Color _logo;
  late Color _logoOnDark;

  static const _primaryPresets = [
    Color(0xFF64B5F6), // 淡い青
    Color(0xFF7986CB), // 淡い藍
    Color(0xFF81C784), // 淡い緑
    Color(0xFFBA68C8), // 淡い紫
    Color(0xFFF06292), // 淡いピンク
    Color(0xFFFFB74D), // 淡いオレンジ
    Color(0xFF90A4AE), // 淡いグレー
    Color(0xFF607D8B), // 少し濃いめのグレー
  ];

  static const _accentPresets = [
    Color(0xFFFFE082), // 淡い黄
    Color(0xFFFFCC80), // 淡いオレンジ
    Color(0xFFEF9A9A), // 淡い赤
    Color(0xFFA5D6A7), // 淡い緑
    Color(0xFF80DEEA), // 淡い水色
    Color(0xFFF48FB1), // 淡いピンク
    Color(0xFFCE93D8), // 淡い紫
    Color(0xFFB0BEC5), // 淡い青灰
  ];

  static const _textPresets = [
    Color(0xFF64B5F6),
    Color(0xFF7986CB),
    Color(0xFF81C784),
    Color(0xFFBA68C8),
    Color(0xFFF06292),
    Color(0xFFFFB74D),
    Color(0xFF90A4AE),
    Color(0xFF607D8B),
  ];

  @override
  void initState() {
    super.initState();
    final tp = context.read<ThemeProvider>();
    _primary = tp.primaryColor;
    _accent = tp.accentColor;
    _text = tp.textColor;
    _logo = tp.logoColor;
    _logoOnDark = tp.logoColorOnDark;
  }

  void _updateColor({Color? primary, Color? accent, Color? text, Color? logo, Color? logoOnDark}) {
    if (primary != null) setState(() => _primary = primary);
    if (accent != null) setState(() => _accent = accent);
    if (text != null) setState(() => _text = text);
    if (logo != null) setState(() => _logo = logo);
    if (logoOnDark != null) setState(() => _logoOnDark = logoOnDark);
    context.read<ThemeProvider>().updateColors(
      primaryColor: primary,
      accentColor: accent,
      textColor: text,
      logoColor: logo,
      logoColorOnDark: logoOnDark,
    );
  }

  Future<void> _save() async {
    final email = context.read<SheetsProvider>().currentUserEmail;
    if (email == null) return;
    try {
      await context.read<ThemeProvider>().saveSettings(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存に失敗しました: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _reset() {
    _updateColor(
      primary: const Color(0xFF047CBC),
      accent: const Color(0xFFF1C232),
      text: const Color(0xFF047CBC),
      logo: const Color(0xFF047CBC),
      logoOnDark: Colors.white,
    );
  }

  Future<void> _showColorPicker({
    required String title,
    required Color current,
    required ValueChanged<Color> onChanged,
  }) async {
    Color temp = current;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: temp,
            onColorChanged: (c) => temp = c,
            enableAlpha: false,
            labelTypes: const [ColorLabelType.hex, ColorLabelType.rgb],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () {
              onChanged(temp);
              Navigator.pop(ctx);
            },
            child: const Text('決定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: const Text('カラー設定', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: TextButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
              label: const Text('初期設定に戻す', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.18),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPreview(),
            const SizedBox(height: 20),
            _buildSection(
              icon: Icons.format_paint,
              label: 'メインカラー',
              description: 'AppBar・ボタン・ボーダーの色',
              selected: _primary,
              presets: _primaryPresets,
              onSelected: (c) => _updateColor(primary: c),
              onCustom: () => _showColorPicker(
                title: 'メインカラー',
                current: _primary,
                onChanged: (c) => _updateColor(primary: c),
              ),
            ),
            const SizedBox(height: 12),
            _buildSection(
              icon: Icons.auto_awesome,
              label: 'アクセントカラー',
              description: '地図アイコン・ハイライトの色',
              selected: _accent,
              presets: _accentPresets,
              onSelected: (c) => _updateColor(accent: c),
              onCustom: () => _showColorPicker(
                title: 'アクセントカラー',
                current: _accent,
                onChanged: (c) => _updateColor(accent: c),
              ),
            ),
            const SizedBox(height: 12),
            _buildSection(
              icon: Icons.image_outlined,
              label: 'ロゴカラー（白背景）',
              description: 'ログイン・カード内などのロゴの色',
              selected: _logo,
              presets: _primaryPresets,
              onSelected: (c) => _updateColor(logo: c),
              onCustom: () => _showColorPicker(
                title: 'ロゴカラー（白背景）',
                current: _logo,
                onChanged: (c) => _updateColor(logo: c),
              ),
            ),
            const SizedBox(height: 12),
            _buildSection(
              icon: Icons.image,
              label: 'ロゴカラー（有色背景）',
              description: 'AppBarなど有色背景上のロゴの色',
              selected: _logoOnDark,
              presets: [
                Colors.white,
                ..._primaryPresets,
              ],
              onSelected: (c) => _updateColor(logoOnDark: c),
              onCustom: () => _showColorPicker(
                title: 'ロゴカラー（有色背景）',
                current: _logoOnDark,
                onChanged: (c) => _updateColor(logoOnDark: c),
              ),
            ),
            const SizedBox(height: 12),
            _buildSection(
              icon: Icons.text_fields,
              label: 'テキストカラー',
              description: 'セクション見出し・ラベルテキストの色',
              selected: _text,
              presets: _textPresets,
              onSelected: (c) => _updateColor(text: c),
              onCustom: () => _showColorPicker(
                title: 'テキストカラー',
                current: _text,
                onChanged: (c) => _updateColor(text: c),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save, size: 20),
                label: const Text('変更を保存', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String label,
    required String description,
    required Color selected,
    required List<Color> presets,
    required ValueChanged<Color> onSelected,
    required VoidCallback onCustom,
  }) {
    final isCustom = !presets.any((c) => c.value == selected.value);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: selected.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: selected),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(description, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ...presets.map((color) {
                final isSelected = color.value == selected.value;
                return GestureDetector(
                  onTap: () => onSelected(color),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.black87 : Colors.grey.shade300,
                        width: isSelected ? 3 : 1,
                      ),
                      boxShadow: isSelected
                          ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8)]
                          : null,
                    ),
                    child: isSelected
                        ? Icon(
                            Icons.check,
                            color: color.computeLuminance() > 0.7 ? Colors.black87 : Colors.white,
                            size: 20,
                          )
                        : null,
                  ),
                );
              }),
              GestureDetector(
                onTap: onCustom,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isCustom ? selected : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isCustom ? Colors.black87 : Colors.grey.shade400,
                      width: isCustom ? 3 : 1,
                    ),
                    boxShadow: isCustom
                        ? [BoxShadow(color: selected.withOpacity(0.4), blurRadius: 8)]
                        : null,
                  ),
                  child: isCustom
                      ? Icon(
                          Icons.check,
                          color: selected.computeLuminance() > 0.7 ? Colors.black87 : Colors.white,
                          size: 20,
                        )
                      : Icon(Icons.colorize, color: Colors.grey.shade500, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_outlined, size: 18, color: Colors.grey.shade700),
              const SizedBox(width: 6),
              const Text('プレビュー', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    color: _primary,
                    child: Row(
                      children: [
                        SvgPicture.asset(
                          'assets/APP_LOGO.svg',
                          width: 22,
                          height: 22,
                          colorFilter: ColorFilter.mode(_logoOnDark, BlendMode.srcIn),
                        ),
                        const SizedBox(width: 8),
                        const Text('AppBar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
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
                        const SizedBox(height: 10),
                        Row(children: [
                          Icon(Icons.location_on, color: _accent, size: 20),
                          const SizedBox(width: 4),
                          const Text('住所テキスト（太字）', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          SvgPicture.asset(
                            'assets/APP_LOGO.svg',
                            width: 26,
                            height: 26,
                            colorFilter: ColorFilter.mode(_logo, BlendMode.srcIn),
                          ),
                          const SizedBox(width: 8),
                          Text('ロゴ（白背景）', style: TextStyle(fontSize: 13, color: _logo, fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('ボタン', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
