import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'portal_screen.dart';
import '../services/auth_service.dart';
import '../providers/sheets_provider.dart';
import 'senkyo_menu_screen.dart';
import 'application_menu_screen.dart';
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
        const MenuItem(
          label: '申請',
          iconAsset: 'assets/申込み.png',
          destination: ApplicationMenuScreen(),
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          const double padding = 16;
          const double spacing = 12;
          const int columns = 3;
          final tileSize = (constraints.maxWidth - padding * 2 - spacing * (columns - 1)) / columns;
          return Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.0,
              ),
              itemCount: menuItems.length,
              itemBuilder: (context, index) {
                final item = menuItems[index];
                return _buildMenuCard(context, item);
              },
            ),
          ),
          if (sheets.isAdmin)
            Positioned(
              left: 16,
              bottom: 16,
              child: SizedBox(
                width: tileSize,
                height: tileSize,
                child: _buildMenuCard(
                  context,
                  MenuItem(
                    label: '管理画面',
                    iconAsset: 'assets/奉仕監督.png',
                    destination: const AdminScreen(),
                    color: cs.secondary,
                  ),
                ),
              ),
            ),
        ],
          );
        },
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
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PortalScreen(email: auth.currentUser?.email))),
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


  Widget _buildMenuCard(BuildContext context, MenuItem item) {
    final bool isEnabled = item.destination != null || item.onTapOverride != null;
    final cs = Theme.of(context).colorScheme;
    final Color activeColor = isEnabled ? (item.color ?? cs.primary) : Colors.grey.shade400;

    return GestureDetector(
      onTap: isEnabled
          ? () {
              if (item.onTapOverride != null) {
                item.onTapOverride!(context);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => item.destination!),
                );
              }
            }
          : null,
      child: Container(
        decoration: BoxDecoration(
          gradient: isEnabled
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, Colors.grey.shade50],
                )
              : null,
          color: isEnabled ? null : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isEnabled ? (item.color ?? cs.primary) : Colors.grey.shade300,
            width: 3,
          ),
          boxShadow: isEnabled
              ? [
                  BoxShadow(
                    color: (item.color ?? cs.primary).withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: Colors.white.withOpacity(0.8),
                    blurRadius: 4,
                    offset: const Offset(0, -1),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            item.iconData != null
                ? Icon(item.iconData, size: 40, color: activeColor)
                : Image.asset(
                    item.iconAsset,
                    width: 40,
                    height: 40,
                    color: activeColor,
                  ),
            const SizedBox(height: 8),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: activeColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
