import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sheets_provider.dart';
import '../services/firestore_service.dart';
import 'sheet_view_screen.dart';

class AllAutolockScreen extends StatefulWidget {
  const AllAutolockScreen({super.key});

  @override
  State<AllAutolockScreen> createState() => _AllAutolockScreenState();
}

class _AllAutolockScreenState extends State<AllAutolockScreen> {
  bool _loading = true;
  String? _error;

  // グループ名 → [ { areaNo, buildings: [{name, buildno}] } ]
  Map<String, List<Map<String, dynamic>>> _groupData = {};
  List<String> _groupOrder = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // 1. 全グループのAUTOLOCK割当: territory → groupName
      final assignments = await FirestoreService.getAllLatestAssignments(type: 'AUTOLOCK');

      // 2. AUTOLOCK_LIST から区域番号 → 物件一覧
      final buildings = await FirestoreService.getAutolockBuildingsDetailed();

      // 3. グループ → [{areaNo, buildings}] に整理
      final grouped = <String, Map<String, List<Map<String, dynamic>>>>{};
      for (final entry in assignments.entries) {
        final territory = entry.key;
        final group = entry.value;
        grouped.putIfAbsent(group, () => {})[territory] =
            buildings[territory] ?? [];
      }

      final result = <String, List<Map<String, dynamic>>>{};
      for (final group in grouped.keys) {
        final areas = grouped[group]!.entries.toList()
          ..sort((a, b) {
            final na = int.tryParse(a.key);
            final nb = int.tryParse(b.key);
            if (na != null && nb != null) return na.compareTo(nb);
            return a.key.compareTo(b.key);
          });
        result[group] = areas
            .map((e) => {'areaNo': e.key, 'buildings': e.value})
            .toList();
      }

      final sortedGroups = result.keys.toList()..sort();

      if (mounted) {
        setState(() {
          _groupData = result;
          _groupOrder = sortedGroups;
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
        title: const Text('オートロック区域'),
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
      body: _buildBody(context, sheets),
    );
  }

  Widget _buildBody(BuildContext context, SheetsProvider sheets) {
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
                setState(() { _loading = true; _error = null; });
                _load();
              },
              child: const Text('再読み込み'),
            ),
          ],
        ),
      );
    }
    if (_groupOrder.isEmpty) {
      return const Center(child: Text('割り当てられたオートロック区域はありません'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _groupOrder.expand((group) {
          final areas = _groupData[group] ?? [];
          return <Widget>[
            _buildGroupTag(context, '${group}グループ'),
            const SizedBox(height: 8),
            ...areas.expand((area) {
              final areaNo = area['areaNo'] as String;
              final bldgs = area['buildings'] as List<Map<String, dynamic>>;
              return <Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '区域No.$areaNo',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                ...bldgs.map((b) {
                  final name = b['name'] as String? ?? '';
                  final buildno = b['buildno'] as String? ?? '';
                  final cardName = '$areaNo-$buildno';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: buildno.isNotEmpty
                          ? () {
                              sheets.selectAutolockCard(cardName);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SheetViewScreen(
                                    isAutolock: true,
                                    displayTitle: name,
                                  ),
                                ),
                              );
                            }
                          : null,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outlined,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                            Icon(Icons.chevron_right,
                                color: Colors.grey.shade400),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
              ];
            }),
            const SizedBox(height: 16),
          ];
        }).toList(),
      ),
    );
  }

  Widget _buildGroupTag(BuildContext context, String label) {
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
}
