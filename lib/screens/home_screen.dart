import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../providers/sheets_provider.dart';
import 'senkyo_menu_screen.dart';
import 'application_menu_screen.dart';
import 'announcement_screen.dart';
import 'admin_screen.dart';
import 'color_settings_screen.dart';

class MenuItem {
  final String label;
  final String iconAsset;
  final Widget? destination;
  final Color? color;
  final IconData? iconData;

  const MenuItem({
    required this.label,
    required this.iconAsset,
    this.destination,
    this.color,
    this.iconData,
  });
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});


  List<MenuItem> _getMenuItems(bool isAdmin) => [
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
        if (isAdmin)
          const MenuItem(
            label: '管理画面',
            iconAsset: 'assets/奉仕監督.png',
            destination: AdminScreen(),
            color: Color(0xFFE0A800),
          ),
        const MenuItem(
          label: '開発用',
          iconAsset: '',
          iconData: Icons.computer,
          color: Color(0xFF888888),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final sheets = context.watch<SheetsProvider>();
    final cs = Theme.of(context).colorScheme;
    final menuItems = _getMenuItems(sheets.isAdmin);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 8,
        leadingWidth: 44,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Image.asset('assets/APP_LOGO_TOP.png'),
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
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: 'カラー設定',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ColorSettingsScreen()),
            ),
          ),
        ],
      ),
      body: Padding(
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
                onTap: () => _openPortal(auth.currentUser?.email),
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

  Future<void> _openPortal(String? email) async {
    String urlString = 'https://sites.google.com/view/karakida/';

    // メールアドレスがある場合は、Google の Account Chooser を経由して
    // ログイン状態を維持しつつ遷移を試みる
    if (email != null && email.isNotEmpty) {
      final encodedEmail = Uri.encodeComponent(email);
      final encodedContinue = Uri.encodeComponent(urlString);
      urlString =
          'https://accounts.google.com/AccountChooser?Email=$encodedEmail&continue=$encodedContinue';
    }

    final Uri url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildMenuCard(BuildContext context, MenuItem item) {
    final bool isEnabled = item.destination != null;
    final cs = Theme.of(context).colorScheme;
    final Color activeColor = isEnabled ? (item.color ?? cs.primary) : Colors.grey.shade400;

    return GestureDetector(
      onTap: isEnabled
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => item.destination!),
              );
            }
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isEnabled ? (item.color ?? cs.primary) : Colors.grey.shade300,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
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
