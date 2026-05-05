import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sheets_provider.dart';
import '../services/firestore_service.dart';
import 'territory_cards_list_screen.dart';

class AllTerritoriesScreen extends StatefulWidget {
  const AllTerritoriesScreen({super.key});

  @override
  State<AllTerritoriesScreen> createState() => _AllTerritoriesScreenState();
}

class _AllTerritoriesScreenState extends State<AllTerritoriesScreen> {
  

  bool _loading = true;
  String? _error;
  Map<String, List<String>> _groupTerritories = {};
  List<String> _groupOrder = [];
  Map<String, String> _territoryGroup = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final assignments = await FirestoreService.getAllLatestAssignments(type: 'NORMAL');
      final grouped = <String, List<String>>{};
      final territoryGroup = <String, String>{};
      for (final entry in assignments.entries) {
        grouped.putIfAbsent(entry.value, () => []).add(entry.key);
        territoryGroup[entry.key] = entry.value;
      }
      for (final group in grouped.keys) {
        grouped[group]!.sort((a, b) {
          final na = int.tryParse(a);
          final nb = int.tryParse(b);
          if (na != null && nb != null) return na.compareTo(nb);
          return a.compareTo(b);
        });
      }
      final sortedGroups = grouped.keys.toList()..sort();
      if (mounted) {
        setState(() {
          _groupTerritories = grouped;
          _groupOrder = sortedGroups;
          _territoryGroup = territoryGroup;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '読み込みに失敗しました: $e';
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
        title: const Text('全ての区域カード'),
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
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
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
                _load();
              },
              child: const Text('再読み込み'),
            ),
          ],
        ),
      );
    }
    if (_groupOrder.isEmpty) {
      return const Center(child: Text('割り当てられた区域はありません'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _groupOrder.expand((group) {
          final territories = _groupTerritories[group] ?? [];
          return <Widget>[
            _buildGroupTag(group),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: territories.map((t) => _buildTerritoryChip(context, t)).toList(),
            ),
            const SizedBox(height: 24),
          ];
        }).toList(),
      ),
    );
  }

  Widget _buildGroupTag(String label) {
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

  Widget _buildTerritoryChip(BuildContext context, String territory) {
    return GestureDetector(
      onTap: () {
        final groupName = _territoryGroup[territory] ?? '';
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TerritoryCardsListScreen(
              groupName: groupName,
              territoryNumber: territory,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5),
        ),
        child: Text(
          territory,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
