import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  bool _refreshing = false;
  String? _error;
  DateTime? _lastUpdated;

  // グループ名 → [ { areaNo, buildings: [{name, buildno}] } ]
  Map<String, List<Map<String, dynamic>>> _groupData = {};
  List<String> _groupOrder = [];

  // cardName → 直近10分以内の訪問者あり
  Set<String> _recentVisitCards = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool isRefresh = false}) async {
    if (isRefresh) {
      setState(() => _refreshing = true);
    }
    try {
      final assignments = await FirestoreService.getAllLatestAssignments(type: 'AUTOLOCK');
      final buildings = await FirestoreService.getAutolockBuildingsDetailed();

      // 直近10分の訪問記録を一括取得
      final since = Timestamp.fromDate(DateTime.now().subtract(const Duration(minutes: 10)));
      final histSnap = await FirebaseFirestore.instance
          .collection('AREA_DATA_AUTOLOCK_HISTORY')
          .where('timestamp', isGreaterThan: since)
          .get();
      final recentCards = <String>{};
      for (final doc in histSnap.docs) {
        final data = doc.data();
        final areaId = data['areaId']?.toString() ?? '';
        final buildNum = data['buildNum']?.toString() ?? '';
        if (areaId.isNotEmpty && buildNum.isNotEmpty) {
          recentCards.add('$areaId-$buildNum');
        }
      }

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
          _recentVisitCards = recentCards;
          _lastUpdated = DateTime.now();
          _loading = false;
          _refreshing = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '読み込みに失敗しました: $e';
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m更新';
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
          if (_lastUpdated != null && !_loading)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  _formatTime(_lastUpdated!),
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
            ),
          if (!_loading)
            IconButton(
              icon: _refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.refresh, color: Colors.white),
              onPressed: _refreshing ? null : () => _load(isRefresh: true),
            ),
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
                  final hasRecentVisit = _recentVisitCards.contains(cardName);
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
                          border: Border.all(
                            color: hasRecentVisit
                                ? Colors.orange
                                : Colors.grey.shade300,
                            width: hasRecentVisit ? 1.5 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
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
                            if (hasRecentVisit) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded,
                                      color: Colors.orange, size: 14),
                                  const SizedBox(width: 4),
                                  const Text(
                                    '10分以内に訪問者あり',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
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
