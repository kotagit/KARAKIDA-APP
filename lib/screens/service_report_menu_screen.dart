import 'package:flutter/material.dart';
import 'service_report_screen.dart';

class ServiceReportMenuScreen extends StatelessWidget {
  const ServiceReportMenuScreen({super.key});

  static const Color _primaryBlue = Color(0xFF047CBC);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('奉仕報告'),
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            _buildMenuButton(
              context,
              label: '自分の報告',
              icon: Icons.person_outline,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ServiceReportScreen(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildMenuButton(
              context,
              label: '他の人の報告',
              icon: Icons.people_outline,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ServiceReportScreen(isOther: true),
                ),
              ),
            ),
          ],
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
          border: Border.all(color: _primaryBlue, width: 2),
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
            Icon(icon, color: _primaryBlue, size: 28),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _primaryBlue,
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, color: _primaryBlue),
          ],
        ),
      ),
    );
  }
}
