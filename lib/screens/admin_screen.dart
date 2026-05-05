import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../providers/sheets_provider.dart';
import 'admin_group_territory_assignment_screen.dart';
import 'admin_overall_assignment_screen.dart';
import 'admin_public_witnessing_screen.dart';
import 'application_screen.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  

  @override
  Widget build(BuildContext context) {
    final sheets = context.watch<SheetsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('管理画面'),
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
            if (sheets.isCho) ...[
              _buildSectionTag(context, '司会者'),
              const SizedBox(height: 8),
              _buildMenuButton(
                context,
                label: '区域カード配布',
                icon: Icons.table_chart_outlined,
                onTap: () {
                  final myGroup = sheets.currentUserGroupName;
                  if (myGroup == null || myGroup.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('あなたのグループ情報が見つかりません')),
                    );
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminOverallAssignmentScreen(groupName: myGroup),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
            if (sheets.isAdmin) ...[
              _buildSectionTag(context, '取決め策定者'),
              const SizedBox(height: 8),
              _buildMenuButton(
                context,
                label: '公共エリア',
                icon: Icons.location_city,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminPublicWitnessingScreen()),
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (sheets.isTerritoryServant) ...[
              _buildSectionTag(context, '区域係'),
              const SizedBox(height: 8),
              _buildMenuButton(
                context,
                label: 'グループ区域割当て',
                icon: Icons.assignment_outlined,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminGroupTerritoryAssignmentScreen()),
                ),
              ),
              const SizedBox(height: 12),
              _buildMenuButton(
                context,
                label: '夜間区域割当て',
                icon: Icons.nightlight_round,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminGroupTerritoryAssignmentScreen(
                      title: '夜間区域割当て',
                      type: 'NIGHT',
                      fixedGroups: ['会衆'],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildMenuButton(
                context,
                label: 'AL区域割当て',
                icon: Icons.lock_outline,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminGroupTerritoryAssignmentScreen(
                      title: 'AL区域割当て',
                      type: 'AUTOLOCK',
                    ),
                  ),
                ),
              ),
            ],
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
