import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../providers/sheets_provider.dart';
import 'territory_detail_screen.dart';
import 'admin_overall_assignment_screen.dart';
import 'admin_group_territory_assignment_screen.dart';
class AdminTerritoryScreen extends StatefulWidget {
  final String groupName;
  final bool isNight;

  const AdminTerritoryScreen({
    super.key,
    required this.groupName,
    this.isNight = false,
  });

  @override
  State<AdminTerritoryScreen> createState() => _AdminTerritoryScreenState();
}

class _AdminTerritoryScreenState extends State<AdminTerritoryScreen> {
  static const Color _primaryBlue = Color(0xFF047CBC);

  List<String> _territories = [];
  Set<String> _fullyAssignedTerritories = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTerritories();
  }

  Future<void> _loadTerritories() async {
    final sheets = context.read<SheetsProvider>();
    try {
      // Load territories for the group from data2 (regular) or data5 (night)
      final list = widget.isNight
          ? await sheets.loadNightTerritoriesForGroup(widget.groupName)
          : await sheets.loadTerritoriesForGroup(widget.groupName);

      // Extract unique territory prefixes (e.g., "1" from "1-7", "50" from "50-4")
      final prefixes = list
          .map((t) => t.split('-')[0].trim())
          .where((p) => p.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => int.tryParse(a)?.compareTo(int.tryParse(b) ?? 0) ?? a.compareTo(b));

      // Check assignment status for each territory
      final assignments = await sheets.getAllAssignmentsForGroup(widget.groupName, isNight: widget.isNight);
      final territoryStatus = <String, bool>{}; // territory -> isFullyAssigned

      // Group assignments by territory
      final grouped = <String, List<Map<String, String>>>{};
      for (final a in assignments) {
        final t = a['territory']!;
        grouped.putIfAbsent(t, () => []);
        grouped[t]!.add(a);
      }

      final fullyAssigned = <String>{};
      for (final prefix in prefixes) {
        final cards = grouped[prefix] ?? [];
        if (cards.isNotEmpty && cards.every((c) => c['memberName'] != '未割当て')) {
          fullyAssigned.add(prefix);
        }
      }

      if (mounted) {
        setState(() {
          _territories = prefixes;
          _fullyAssignedTerritories = fullyAssigned;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '区域情報の読み込みに失敗しました';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheets = context.watch<SheetsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNight
            ? '夜間区域'
            : '${widget.groupName}グループ'),
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
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                widget.isNight
                    ? '夜間区域に割り当てられた区域番号を読み込んでいます。'
                    : 'グループに割り当てられた区域番号を読み込んでいます。',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _loadTerritories();
              },
              child: const Text('再読み込み'),
            ),
          ],
        ),
      );
    }
    if (_territories.isEmpty) {
      return const Center(child: Text('割当て区域が見つかりませんでした'));
    }

    final sheets = context.watch<SheetsProvider>();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.isNight) ...[
            _buildMenuButton(
              icon: Icons.table_chart,
              label: '区域カード配布',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminOverallAssignmentScreen(
                      groupName: widget.groupName,
                      isNight: widget.isNight,
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMenuButton({
    required IconData icon,
    required String label,
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
                color: Color(0xFF047CBC),
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, color: Color(0xFF047CBC)),
          ],
        ),
      ),
    );
  }

  Widget _buildTerritoryButton(String number) {
    final isFullyAssigned = _fullyAssignedTerritories.contains(number);

    return SizedBox(
      width: 88,
      height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: _primaryBlue,
          side: BorderSide(
            color: _primaryBlue,
            width: 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TerritoryDetailScreen(
                territoryNumber: number,
                groupName: widget.groupName,
                isNight: widget.isNight,
              ),
            ),
          ).then((_) => _loadTerritories());
        },
        child: Text(
          number,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: _primaryBlue,
          ),
        ),
      ),
    );
  }
}
