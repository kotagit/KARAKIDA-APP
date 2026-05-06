import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../providers/sheets_provider.dart';
import 'file_list_screen.dart';
import 'night_territory_cards_screen.dart';
import 'all_territories_screen.dart';
import 'public_witnessing_table_screen.dart';

class SenkyoMenuScreen extends StatelessWidget {
  const SenkyoMenuScreen({super.key});

  

  @override
  Widget build(BuildContext context) {
    final sheets = context.watch<SheetsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('宣教'),
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        actions: [
          if (sheets.currentUserName != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  sheets.currentUserName!,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionTag(context, '区域情報'),
            const SizedBox(height: 8),
            _buildMenuButton(
              context,
              label: 'マイ区域カード',
              icon: Icons.map_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FileListScreen()),
              ),
            ),
            const SizedBox(height: 12),
            _buildMenuButton(
              context,
              label: 'オートロック区域',
              icon: Icons.lock_person_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NightTerritoryCardsScreen(
                    type: 'AUTOLOCK',
                    title: 'オートロック区域',
                    cardIcon: Icons.lock_person_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildMenuButton(
              context,
              label: '夜間区域',
              icon: Icons.nightlight_round_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NightTerritoryCardsScreen(),
                ),
              ),
            ),
            const SizedBox(height: 32),
            _buildSectionTag(context, '取決表'),
            const SizedBox(height: 8),
            _buildMenuButton(
              context,
              label: '公共エリア伝道',
              icon: Icons.location_city,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PublicWitnessingTableScreen()),
              ),
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
    Color? accentColor,
  }) {
    final color = accentColor ?? Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color, width: 2),
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
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    );
  }
}
