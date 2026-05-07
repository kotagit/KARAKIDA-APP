import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sheets_provider.dart';
import '../services/firestore_service.dart';
import 'sheet_view_screen.dart';

class TerritoryCardsListScreen extends StatefulWidget {
  final String groupName;
  final String territoryNumber;

  const TerritoryCardsListScreen({
    super.key,
    required this.groupName,
    required this.territoryNumber,
  });

  @override
  State<TerritoryCardsListScreen> createState() => _TerritoryCardsListScreenState();
}

class _TerritoryCardsListScreenState extends State<TerritoryCardsListScreen> {
  

  bool _loading = true;
  String? _error;
  // memberName -> list of cardNames (empty string key = unassigned)
  Map<String, List<String>> _memberCards = {};
  List<String> _memberOrder = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // 1. カード一覧取得（キャッシュ優先）
      final cards = await FirestoreService.getCardsForTerritory(widget.territoryNumber);

      // 2. カード割当てをフィールド検索で取得（旧・新ドキュメントID両対応）
      final assignments = await FirestoreService.getAssignmentsForTerritory(
        widget.groupName,
        widget.territoryNumber,
      );
      final assignmentMap = <String, String>{};
      for (final a in assignments) {
        final id = FirestoreService.cardNameFromDoc(a);
        final member = a['memberName']?.toString() ?? '';
        if (id.isNotEmpty && member.isNotEmpty) assignmentMap[id] = member;
      }

      final grouped = <String, List<String>>{};
      for (final card in cards) {
        final id = card['id'] as String? ?? '';
        if (id.isEmpty) continue;
        final member = assignmentMap[id] ?? '';
        grouped.putIfAbsent(member, () => []).add(id);
      }

      for (final key in grouped.keys) {
        grouped[key]!.sort((a, b) {
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
      }

      // assigned members sorted, unassigned last
      final members = grouped.keys.where((k) => k.isNotEmpty).toList()..sort();

      if (mounted) {
        setState(() {
          _memberCards = grouped;
          _memberOrder = members;
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
        title: Text('区域No.${widget.territoryNumber}'),
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
    if (_memberOrder.isEmpty) {
      return const Center(child: Text('カードが見つかりません'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _memberOrder.expand((member) {
          final cardNames = _memberCards[member] ?? [];
          final label = member.isEmpty ? '未割当て' : member;
          return <Widget>[
            _buildMemberTag(label),
            const SizedBox(height: 8),
            ...cardNames.map((cardName) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () {
                  sheets.selectCard(cardName);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SheetViewScreen(
                        isNight: false,
                        assignedMemberName: member.isEmpty ? null : member,
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Row(
                    children: [
                      Icon(Icons.map_outlined, color: Theme.of(context).colorScheme.primary),
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
                      Icon(Icons.chevron_right, color: Colors.grey.shade400),
                    ],
                  ),
                ),
              ),
            )),
            const SizedBox(height: 16),
          ];
        }).toList(),
      ),
    );
  }

  Widget _buildMemberTag(String label) {
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
