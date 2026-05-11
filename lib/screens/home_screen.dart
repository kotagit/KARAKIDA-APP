import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../providers/sheets_provider.dart';
import 'senkyo_menu_screen.dart';
import 'announcement_screen.dart';
import 'admin_screen.dart';
import 'color_settings_screen.dart';
import 'support_screen.dart';
import '../providers/theme_provider.dart';

class MenuItem {
  final String label;
  final String iconAsset;
  final Widget? destination;
  final Color? color;
  final IconData? iconData;
  final Future<void> Function(BuildContext)? onTapOverride;

  const MenuItem({
    required this.label,
    required this.iconAsset,
    this.destination,
    this.color,
    this.iconData,
    this.onTapOverride,
  });
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});


  List<MenuItem> _getMenuItems(bool isAdmin, ColorScheme cs) => [
        const MenuItem(
          label: '発表',
          iconAsset: 'assets/最新情報.png',
          destination: AnnouncementScreen(),
        ),
        const MenuItem(
          label: '宣教',
          iconAsset: 'assets/宣教.png',
          destination: SenkyoMenuScreen(),
        ),
        MenuItem(
          label: '支援',
          iconAsset: '',
          iconData: Icons.handshake_outlined,
          destination: const SupportScreen(),
          onTapOverride: (context) async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                content: const Text(
                  'この機能は他の人を援助する際にだけご利用下さい。\n\nそれ以外の場合はご自身のグループに割り当てられた通常区域またはオートロック区域の区域カードをご使用ください。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('戻る'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('理解しました'),
                  ),
                ],
              ),
            );
            if (ok == true && context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SupportScreen()),
              );
            }
          },
        ),
        const MenuItem(
          label: '設定',
          iconAsset: '',
          iconData: Icons.palette_outlined,
          destination: ColorSettingsScreen(),
        ),
        MenuItem(
          label: '唐木田PORTAL',
          iconAsset: '',
          iconData: Icons.language,
          onTapOverride: (context) async {
            final uri = Uri.parse('https://karakida-app-7bbc0.web.app');
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final sheets = context.watch<SheetsProvider>();
    final cs = Theme.of(context).colorScheme;
    final menuItems = _getMenuItems(sheets.isAdmin, cs);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 8,
        leadingWidth: 44,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: SvgPicture.asset(
            'assets/APP_LOGO.svg',
            colorFilter: ColorFilter.mode(
              context.watch<ThemeProvider>().logoColorOnDark,
              BlendMode.srcIn,
            ),
          ),
        ),
        title: const Text('唐木田APP', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        actions: [
          if (sheets.currentUserName != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  sheets.currentUserName!,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: _buildHomeListMenu(context, menuItems, sheets.isAdmin),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        color: cs.primary,
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  final uri = Uri.parse('https://karakida-app-7bbc0.web.app');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.language, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      '唐木田PORTAL',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: 1,
              height: 24,
              color: Colors.white.withOpacity(0.3),
            ),
            Expanded(
              child: InkWell(
                onTap: () async {
                  await auth.signOut();
                  if (context.mounted) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'ログアウト',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildHomeListMenu(BuildContext context, List<MenuItem> items, bool isAdmin) {
    final cs = Theme.of(context).colorScheme;
    final tiles = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      tiles.add(_buildTile(context, items[i]));
      tiles.add(const SizedBox(height: 12));
    }
    if (isAdmin) {
      tiles.add(_buildTile(
        context,
        MenuItem(
          label: '管理画面',
          iconAsset: 'assets/奉仕監督.png',
          destination: const AdminScreen(),
          color: cs.secondary,
        ),
        isAdminRow: true,
      ));
    } else if (tiles.isNotEmpty) {
      tiles.removeLast(); // 末尾の余白を削除
    }

    return Column(children: tiles);
  }

  Widget _buildTile(
    BuildContext context,
    MenuItem item, {
    bool isAdminRow = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final bool isEnabled = item.destination != null || item.onTapOverride != null;
    const Color adminColor = Color(0xFFF1C232);
    final Color tileColor = isAdminRow
        ? adminColor
        : (isEnabled ? (item.color ?? cs.primary) : Colors.grey.shade400);

    return _PressableTile(
      tileColor: tileColor,
      isEnabled: isEnabled,
      onTap: () {
        if (item.onTapOverride != null) {
          item.onTapOverride!(context);
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => item.destination!),
          );
        }
      },
      child: Row(
        children: [
          item.iconData != null
              ? Icon(item.iconData, size: 30, color: tileColor)
              : Image.asset(
                  item.iconAsset,
                  width: 30,
                  height: 30,
                  color: tileColor,
                ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              item.label,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: tileColor,
              ),
            ),
          ),
          Icon(
            Icons.chevron_right,
            size: 24,
            color: tileColor.withOpacity(0.5),
          ),
        ],
      ),
    );
  }
}

class _PressableTile extends StatefulWidget {
  final Color tileColor;
  final bool isEnabled;
  final VoidCallback onTap;
  final Widget child;

  const _PressableTile({
    required this.tileColor,
    required this.isEnabled,
    required this.onTap,
    required this.child,
  });

  @override
  State<_PressableTile> createState() => _PressableTileState();
}

class _PressableTileState extends State<_PressableTile> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (!widget.isEnabled) return;
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.isEnabled ? widget.onTap : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _pressed
                ? widget.tileColor.withOpacity(0.06)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: widget.tileColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: widget.tileColor.withOpacity(_pressed ? 0.10 : 0.22),
                blurRadius: _pressed ? 4 : 10,
                offset: Offset(0, _pressed ? 1 : 3),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
          child: widget.child,
        ),
      ),
    );
  }
}
