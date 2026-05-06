import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'application_screen.dart';
import 'application_result_screen.dart';
import 'service_report_screen.dart';
import 'service_report_result_screen.dart';
import 'area_info_registration_screen.dart';

class ApplicationMenuScreen extends StatelessWidget {
  const ApplicationMenuScreen({super.key});

  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('申請'),
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionTag(context, '新規申込'),
            const SizedBox(height: 8),
            _buildMenuButton(
              context,
              label: '公共エリア',
              icon: Icons.location_city,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ApplicationScreen()),
              ),
            ),
            const SizedBox(height: 12),
            _buildMenuButton(
              context,
              label: '奉仕報告',
              icon: Icons.assignment_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ServiceReportScreen()),
              ),
            ),
            const SizedBox(height: 28),
            _buildSectionTag(context, '提出内容'),
            const SizedBox(height: 8),
            _buildMenuButton(
              context,
              label: '公共エリア申込結果',
              icon: Icons.check_circle_outline,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ApplicationResultScreen()),
              ),
            ),
            const SizedBox(height: 12),
            _buildMenuButton(
              context,
              label: '奉仕報告提出結果',
              icon: Icons.assignment_turned_in_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ServiceReportResultScreen()),
              ),
            ),
            const SizedBox(height: 28),
            _buildSectionTag(context, '情報登録'),
            const SizedBox(height: 8),
            _buildMenuButton(
               context,
               label: '区域情報登録',
               icon: Icons.app_registration,
               onTap: () => Navigator.push(
                 context,
                 MaterialPageRoute(
                     builder: (_) => const AreaInfoRegistrationScreen()),
               ),
             ),
             const SizedBox(height: 12),
             _buildMenuButton(
               context,
               label: '緊急連絡先登録',
               icon: Icons.contact_phone_outlined,
               onTap: () {
                 // TODO: 緊急連絡先登録の画面へ遷移
                 ScaffoldMessenger.of(context).showSnackBar(
                   const SnackBar(content: Text('緊急連絡先登録機能は準備中です')),
                 );
               },
             ),
           ],
        ),
      ),
    );
  }

  Widget _buildSectionTag(BuildContext context, String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
