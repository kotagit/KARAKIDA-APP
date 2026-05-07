import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../providers/sheets_provider.dart';
import 'sheet_view_screen.dart';

/// 夜間区域 / オートロック区域:
/// GROUP_ASS_NO で会衆に type=NIGHT または type=AUTOLOCK として
/// 割り当てられた区域のカード一覧を表示
class NightTerritoryCardsScreen extends StatefulWidget {
  final String type;
  final String title;
  final IconData cardIcon;
  final bool showAllGroups;

  const NightTerritoryCardsScreen({
    super.key,
    this.type = 'NIGHT',
    this.title = '夜間区域',
    this.cardIcon = Icons.nightlight_round,
    this.showAllGroups = false,
  });

  @override
  State<NightTerritoryCardsScreen> createState() => _NightTerritoryCardsScreenState();
}

class _NightTerritoryCardsScreenState extends State<NightTerritoryCardsScreen> {
  

  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<String> _territories = [];
  Map<String, List<String>> _cardsByTerritory = {};
  Map<String, List<Map<String, dynamic>>> _autolockBuildings = {};
  String? _selectedTerritory;
  Set<String> _recentVisitCards = {};
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool isRefresh = false}) async {
    if (isRefresh) setState(() => _refreshing = true);
    try {
      final groupName = widget.type == 'AUTOLOCK'
          ? (context.read<SheetsProvider>().currentUserGroupName ?? '')
          : '会衆';
      final rawTerritories = await FirestoreService.getTerritoriesForGroup(
        groupName,
        type: widget.type,
        currentOnly: true,
      );

      final prefixes = rawTerritories
          .map((e) => e.split('-')[0].trim())
          .where((p) => p.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) {
          final na = int.tryParse(a);
          final nb = int.tryParse(b);
          if (na != null && nb != null) return na.compareTo(nb);
          return a.compareTo(b);
        });

      final cardsByTerritory = <String, List<String>>{};
      for (final t in prefixes) {
        final cards = widget.type == 'NIGHT'
            ? await FirestoreService.getNightCardsForTerritory(t)
            : await FirestoreService.getCardsForTerritory(t);
        final names = cards
            .map((c) => c['id'] as String? ?? '')
            .where((s) => s.isNotEmpty)
            .toList()
          ..sort((a, b) {
            final ra = RegExp(r'(\d+)-(\d+)').firstMatch(a);
            final rb = RegExp(r'(\d+)-(\d+)').firstMatch(b);
            if (ra != null && rb != null) {
              final a1 = int.parse(ra.group(1)!);
              final b1 = int.parse(rb.group(1)!);
              if (a1 != b1) return a1.compareTo(b1);
              return int.parse(ra.group(2)!).compareTo(int.parse(rb.group(2)!));
            }
            return a.compareTo(b);
          });
        cardsByTerritory[t] = names;
      }

      final buildings = widget.type == 'AUTOLOCK'
          ? await FirestoreService.getAutolockBuildingsDetailed()
          : <String, List<Map<String, dynamic>>>{};

      // AUTOLOCK のみ直近10分の訪問記録を一括取得
      final recentCards = <String>{};
      if (widget.type == 'AUTOLOCK') {
        final since = Timestamp.fromDate(
            DateTime.now().subtract(const Duration(minutes: 10)));
        final histSnap = await FirebaseFirestore.instance
            .collection('AREA_DATA_AUTOLOCK_HISTORY')
            .where('timestamp', isGreaterThan: since)
            .get();
        for (final doc in histSnap.docs) {
          final data = doc.data();
          final areaId = data['areaId']?.toString() ?? '';
          final buildNum = data['buildNum']?.toString() ?? '';
          if (areaId.isNotEmpty && buildNum.isNotEmpty) {
            recentCards.add('$areaId-$buildNum');
          }
        }
      }

      if (mounted) {
        setState(() {
          _territories = prefixes;
          _cardsByTerritory = cardsByTerritory;
          _autolockBuildings = buildings;
          _recentVisitCards = recentCards;
          _lastUpdated = DateTime.now();
          _selectedTerritory = prefixes.isNotEmpty ? prefixes.first : null;
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
        title: Text(widget.title),
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        actions: [
          if (widget.type == 'AUTOLOCK' && _lastUpdated != null && !_loading)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  _formatTime(_lastUpdated!),
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
            ),
          if (widget.type == 'AUTOLOCK' && !_loading)
            IconButton(
              icon: _refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
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
      body: _buildBody(sheets),
    );
  }

  Widget _buildBody(SheetsProvider sheets) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
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
                _load();
              },
              child: const Text('再読み込み'),
            ),
          ],
        ),
      );
    }
    if (_territories.isEmpty) {
      return Center(child: Text('${widget.title}に割り当てられたカードはありません'));
    }

    final visibleTerritories = _selectedTerritory == null
        ? _territories
        : _territories.where((t) => t == _selectedTerritory).toList();

    final totalCards = _territories
        .map((t) => _cardsByTerritory[t]?.length ?? 0)
        .fold<int>(0, (a, b) => a + b);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 区域番号ボタン
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _territories.map((t) {
              final isSelected = _selectedTerritory == t;
              return SizedBox(
                width: 64,
                height: 40,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSelected ? Theme.of(context).colorScheme.primary : Colors.white,
                    foregroundColor: isSelected ? Colors.white : Theme.of(context).colorScheme.primary,
                    padding: EdgeInsets.zero,
                    side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 1,
                  ),
                  onPressed: () {
                    setState(() {
                      _selectedTerritory = t;
                    });
                  },
                  child: Text(
                    t,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Text(
            '合計: ${totalCards}カード',
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ...visibleTerritories.map((territory) {
            final cards = _cardsByTerritory[territory] ?? [];
            final buildings = _autolockBuildings[territory] ?? [];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.type == 'AUTOLOCK'
                        ? '区域No.$territory (${buildings.length}棟)'
                        : '区域No.$territory (${cards.length}カード)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.type == 'AUTOLOCK') ...buildings.map((building) {
                  final name = building['name'] as String? ?? '';
                  final buildno = building['buildno'] as String? ?? '';
                  final cardName = '$territory-$buildno';
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
                            color: hasRecentVisit ? Colors.orange : Colors.grey.shade300,
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(
                          children: [
                            Icon(widget.cardIcon, color: Theme.of(context).colorScheme.primary),
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
                            Icon(Icons.chevron_right, color: Colors.grey.shade400),
                          ],
                        ),
                        if (hasRecentVisit) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: const [
                              Icon(Icons.warning_amber_rounded,
                                  color: Colors.orange, size: 14),
                              SizedBox(width: 4),
                              Text(
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
                if (widget.type != 'AUTOLOCK') ...cards.map((cardName) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () {
                        if (widget.type == 'NIGHT') {
                          sheets.selectNightCard(cardName);
                        } else {
                          sheets.selectCard(cardName);
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SheetViewScreen(
                              isNight: widget.type == 'NIGHT',
                            ),
                          ),
                        );
                      },
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
                            Icon(widget.cardIcon, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '区域No.$cardName',
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
                const SizedBox(height: 16),
              ],
            );
          }),
        ],
      ),
    );
  }
}
