import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../providers/sheets_provider.dart';
import 'sheet_view_screen.dart';
class AdminOverallAssignmentScreen extends StatefulWidget {
  final String groupName;
  final bool isNight;

  const AdminOverallAssignmentScreen({
    super.key,
    required this.groupName,
    this.isNight = false,
  });

  @override
  State<AdminOverallAssignmentScreen> createState() =>
      _AdminOverallAssignmentScreenState();
}

class _AdminOverallAssignmentScreenState
    extends State<AdminOverallAssignmentScreen> {
  

  List<Map<String, String>> _assignments = [];
  List<String> _groupMembers = [];
  List<String> _allTerritories = [];
  Map<String, String?> _selectedMembers = {}; // cardName -> memberName
  Map<String, String?> _initialAssignments = {}; // cardName -> memberName
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  String? _selectedTerritory;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final sheets = context.read<SheetsProvider>();
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      // 割当て情報とグループメンバーを並列で取得
      final results = await Future.wait([
        sheets.getAllAssignmentsForGroup(widget.groupName, isNight: widget.isNight),
        sheets.loadGroupMembers(widget.groupName),
      ]);

      final assignments = results[0] as List<Map<String, String>>;
      final members = results[1] as List<String>;

      // 区域番号一覧は assignments から導出（別途Firestoreクエリ不要）
      final territoryPrefixes = assignments
          .map((a) => a['territory']!)
          .where((p) => p.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) {
          final na = int.tryParse(a);
          final nb = int.tryParse(b);
          if (na != null && nb != null) return na.compareTo(nb);
          return a.compareTo(b);
        });

      if (mounted) {
        setState(() {
          _assignments = assignments;
          _groupMembers = members;
          _allTerritories = territoryPrefixes;
          
          // 選択状態の初期化
          _selectedMembers = {};
          _initialAssignments = {};
          for (var a in assignments) {
            final cardName = a['cardName']!;
            final memberName = a['memberName']!;
            _selectedMembers[cardName] = memberName;
            _initialAssignments[cardName] = memberName;
          }
          
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'データの読み込みに失敗しました: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveAll() async {
    final sheets = context.read<SheetsProvider>();
    final changes = <String, List<List<dynamic>>>{}; // territory -> [[card, member], ...]

    // 変更があったものを抽出
    _selectedMembers.forEach((cardName, memberName) {
      if (memberName != _initialAssignments[cardName]) {
        // カード名から区域番号を抽出 (例: "1-1" -> "1")
        final territory = cardName.split('-')[0];
        changes.putIfAbsent(territory, () => []);
        changes[territory]!.add([cardName, memberName ?? '未割当て']);
      }
    });

    if (changes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('変更はありません')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 区域ごとに保存処理を実行
      for (final entry in changes.entries) {
        await sheets.saveGroupMembersToData3(
          widget.groupName,
          entry.key,
          entry.value,
          isNight: widget.isNight,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('全ての変更を保存しました')),
        );
        _loadData(); // 再読み込み
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存に失敗しました: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final hasChanges = _selectedMembers.entries.any((e) => e.value != _initialAssignments[e.key]);

    return Scaffold(
      appBar: AppBar(
        leading: _selectedTerritory != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => setState(() => _selectedTerritory = null),
              )
            : null,
        title: Text(_selectedTerritory != null
            ? '区域No.$_selectedTerritory'
            : widget.isNight
                ? '夜間 (${widget.groupName}) 一括割当て'
                : '${widget.groupName} 一括割当て'),
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        actions: [
          if (hasChanges && !_isLoading)
            IconButton(
              icon: _isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save),
              onPressed: _isSaving ? null : _saveAll,
              tooltip: '一括保存',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                _loadData();
              },
              child: const Text('再読み込み'),
            ),
          ],
        ),
      );
    }

    // Group by territory
    final grouped = <String, List<Map<String, String>>>{};
    for (final assignment in _assignments) {
      final territory = assignment['territory']!;
      grouped.putIfAbsent(territory, () => []);
      grouped[territory]!.add(assignment);
    }

    // Sort territories numerically
    final sortedTerritories = grouped.keys.toList()
      ..sort((a, b) {
        final na = int.tryParse(a);
        final nb = int.tryParse(b);
        if (na != null && nb != null) return na.compareTo(nb);
        return a.compareTo(b);
      });

    // 区域未選択: ボタン一覧のみ表示
    if (_selectedTerritory == null) {
      if (_isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_allTerritories.isEmpty) {
        return const Center(child: Text('割当て情報がありません'));
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const double itemSize = 68.0;
            const double spacing = 8.0;
            final itemsPerRow = ((constraints.maxWidth + spacing) / (itemSize + spacing)).floor();
            final remainder = _allTerritories.length % itemsPerRow;
            final dummies = remainder == 0 ? 0 : itemsPerRow - remainder;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              alignment: WrapAlignment.center,
              children: [
                ..._allTerritories.map((t) {
                  return GestureDetector(
                    onTap: () => setState(() => _selectedTerritory = t),
                    child: Container(
                      width: itemSize,
                      height: itemSize,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        t,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  );
                }),
                ...List.generate(dummies, (_) => const SizedBox(width: itemSize, height: itemSize)),
              ],
            );
          },
        ),
      );
    }

    // 区域選択済み: 該当区域のカード情報のみ表示
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isLoading || _isSaving)
            const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          if (_assignments.isEmpty && _isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('読み込み中...')),
            )
          else if (_assignments.isEmpty)
            const Center(child: Text('割当て情報がありません'))
          else
            ...sortedTerritories.where((t) => t == _selectedTerritory).map((territory) {
              final cards = grouped[territory]!;
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
                      '区域No.$territory (${cards.length}カード)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Table(
                    columnWidths: const {
                      0: FlexColumnWidth(1),
                      1: FlexColumnWidth(2),
                    },
                    border: TableBorder(
                      horizontalInside: BorderSide(color: Colors.grey.shade200),
                    ),
                    children: cards.map((card) {
                      final cardName = card['cardName']!;
                      final currentMember = _selectedMembers[cardName];
                      final isChanged = currentMember != _initialAssignments[cardName];

                      return TableRow(
                        children: [
                          GestureDetector(
                            onTap: () {
                              final sheets = context.read<SheetsProvider>();
                              sheets.selectCard(cardName);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SheetViewScreen(),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              child: Row(
                                children: [
                                  Text(
                                    cardName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Theme.of(context).colorScheme.primary,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Icon(Icons.open_in_new, size: 14, color: Theme.of(context).colorScheme.primary),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: currentMember == 'グループ区域'
                                    ? 'グループ区域'
                                    : ((_groupMembers.contains(currentMember)) ? currentMember : '未割当て'),
                                isExpanded: true,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: currentMember == '未割当て'
                                      ? Colors.grey
                                      : currentMember == 'グループ区域'
                                          ? Theme.of(context).colorScheme.primary
                                          : (isChanged ? Colors.orange.shade800 : Colors.black),
                                  fontWeight: isChanged ? FontWeight.bold : FontWeight.normal,
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: '未割当て',
                                    child: Text('未割当て'),
                                  ),
                                  const DropdownMenuItem(
                                    value: 'グループ区域',
                                    child: Text('グループ区域'),
                                  ),
                                  ..._groupMembers.map((m) => DropdownMenuItem(
                                        value: m,
                                        child: Text(m),
                                      )),
                                ],
                                onChanged: _isSaving ? null : (val) {
                                  if (val != null) {
                                    setState(() {
                                      _selectedMembers[cardName] = val;
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            }).toList(),
        ],
      ),
    );
  }
}
