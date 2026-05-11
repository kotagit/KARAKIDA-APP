import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../providers/sheets_provider.dart';
import '../providers/theme_provider.dart';
import 'sheet_view_screen.dart';

class TerritoryDetailScreen extends StatefulWidget {
  final String territoryNumber;
  final String groupName;
  final bool isNight;

  const TerritoryDetailScreen({
    super.key,
    required this.territoryNumber,
    required this.groupName,
    this.isNight = false,
  });

  @override
  State<TerritoryDetailScreen> createState() => _TerritoryDetailScreenState();
}

class _TerritoryDetailScreenState extends State<TerritoryDetailScreen> {
  
  

  List<String> _cardMembers = [];
  List<Map<String, dynamic>> _cardFiles = [];
  bool _loading = true;
  bool _isReassignMode = false;
  String? _error;
  Map<String, String?> _selectedMembers = {};
  Map<String, String?> _initialAssignments = {};

  @override
  void initState() {
    super.initState();
    _loadCardMembers();
  }

  Future<void> _loadCardMembers({bool forceShowAll = false}) async {
    final sheets = context.read<SheetsProvider>();
    try {
      // 3つのリクエストを同時に開始して並列処理する
      final results = await Future.wait([
        if (!widget.isNight)
          sheets.loadGroupMembers(widget.groupName)
        else
          Future.value(<String>[]),
          
        sheets.getTerritoryCardFiles(
          widget.groupName,
          widget.territoryNumber,
          isNight: widget.isNight,
        ),
        
        sheets.getAssignmentsForTerritory(
          widget.groupName,
          widget.territoryNumber,
          isNight: widget.isNight,
        ),
      ]);

      final members = results[0] as List<String>;
      final cards = results[1] as List<Map<String, dynamic>>;
      final currentAssignments = results[2] as Map<String, String?>;

      final initialAssignments = Map<String, String?>.from(currentAssignments);
      forceShowAll = true;

      if (mounted) {
        setState(() {
          _cardMembers = members;
          _cardFiles = cards;
          _selectedMembers = Map.from(initialAssignments);
          _initialAssignments = Map.from(initialAssignments);
          _isReassignMode = forceShowAll;
          _loading = false;
          if (!forceShowAll && cards.isEmpty) {
            _error = 'すべてのカードに担当者が割当てられています';
          } else {
            _error = null;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'メンバー情報の読み込みに失敗しました: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheets = context.watch<SheetsProvider>();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final hasUnsaved = _selectedMembers.values.any(
          (v) => v != null && v.trim().isNotEmpty,
        );
        if (hasUnsaved) {
          final shouldPop = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('確認'),
              content: const Text('保存されていない割当てがあります。\n保存せずに戻りますか？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('戻る', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
          if (shouldPop == true && context.mounted) {
            Navigator.of(context).pop();
          }
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isNight
              ? 'No. ${widget.territoryNumber}'
              : '${widget.groupName} 区域No. ${widget.territoryNumber}'),
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
      ),
    );
  }

  Future<void> _saveAssignments() async {
    final sheets = context.read<SheetsProvider>();
    try {
      final rowsToWrite = <List<dynamic>>[];

      for (final card in _cardFiles) {
        final cardName = card['id'] as String? ?? '';
        final normalizedCardName = _norm(cardName);
        final selectedMember = _selectedMembers[normalizedCardName];
        final initialMember = _initialAssignments[normalizedCardName];

        if (selectedMember != initialMember) {
          if (selectedMember != null && selectedMember.trim().isNotEmpty) {
            rowsToWrite.add([cardName, selectedMember]);
          }
        }
      }

      if (rowsToWrite.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('担当者が選択されていません')),
        );
        return;
      }

      await sheets.saveGroupMembersToData3(
        widget.groupName,
        widget.territoryNumber,
        rowsToWrite,
        isNight: widget.isNight,
      );

      if (mounted) {
        final savedCardsMap = Map.fromEntries(
          rowsToWrite.map((r) => MapEntry(r[0].toString(), r[1].toString())),
        );

        setState(() {
          if (_isReassignMode) {
            savedCardsMap.forEach((name, member) {
              _initialAssignments[_norm(name)] = member;
            });
          } else {
            final savedNames = savedCardsMap.keys.toSet();
            _cardFiles.removeWhere((c) => savedNames.contains(c['id']));
            for (final name in savedNames) {
              _selectedMembers.remove(_norm(name));
              _initialAssignments.remove(_norm(name));
            }
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存しました')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存に失敗しました: $e')),
        );
      }
    }
  }

  String _norm(String s) => s.trim().replaceAll(RegExp(r'[−–ー]'), '-');

  String _formatCardName(String name) {
    final normalized = name.replaceAll(RegExp(r'[−–ー]'), '-');
    return '区域No.$normalized';
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error == 'すべてのカードに担当者が割当てられています')
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.refresh, size: 24),
                    label: const Text(
                      '再割当てを行う',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.secondary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 4,
                    ),
                    onPressed: () {
                      setState(() { _loading = true; _error = null; });
                      _loadCardMembers(forceShowAll: true);
                    },
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center, maxLines: null),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() { _loading = true; _error = null; });
                _loadCardMembers();
              },
              child: const Text('再読み込み'),
            ),
          ],
        ),
      );
    }
    if (_cardMembers.isEmpty && !widget.isNight) {
      return const Center(child: Text('メンバーが見つかりませんでした'));
    }

    final sheets = context.read<SheetsProvider>();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!widget.isNight) ...[
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                icon: Icon(Icons.save, size: 24),
                label: const Text('保存して反映する', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 4,
                ),
                onPressed: _saveAssignments,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (!widget.isNight && !_isReassignMode) ...[
            const Text(
              '未割当てカードだけが表示されています。\n保存ボタンを押すと反映されます。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 16),
          ],
          if (widget.isNight) const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: _cardFiles.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final card = _cardFiles[index];
                final cardName = card['id'] as String? ?? '';
                if (widget.isNight) {
                  return GestureDetector(
                    onTap: () {
                      sheets.selectCard(cardName);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SheetViewScreen(isNight: widget.isNight),
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
                          SvgPicture.asset(
                            'assets/APP_LOGO.svg',
                            width: 28,
                            height: 28,
                            colorFilter: ColorFilter.mode(
                              context.watch<ThemeProvider>().logoColor,
                              BlendMode.srcIn,
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _formatCardName(cardName),
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                            ),
                          ),
                          Icon(Icons.chevron_right, color: Colors.grey.shade400),
                        ],
                      ),
                    ),
                  );
                } else {
                  return _buildMemberCard(cardName);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberCard(String cardFileName) {
    final normalizedCardName = _norm(cardFileName);
    final selectedValue = _selectedMembers[normalizedCardName];
    final isChanged = _isReassignMode && selectedValue != _initialAssignments[normalizedCardName];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 90,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
              border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                cardFileName,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary, letterSpacing: 0.5),
              ),
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isChanged ? Colors.green.shade50 : null,
                border: Border.all(
                  color: isChanged ? Colors.green.shade300 : Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  width: isChanged ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: DropdownButton<String>(
                isExpanded: true,
                value: selectedValue,
                hint: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text('メンバーを選択', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                ),
                items: [
                  const DropdownMenuItem(
                    value: 'グループ区域',
                    child: Padding(
                      padding: EdgeInsets.only(left: 12),
                      child: Text('グループ区域', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w500)),
                    ),
                  ),
                  ..._cardMembers.map((member) {
                    return DropdownMenuItem(value: member, child: Padding(padding: const EdgeInsets.only(left: 12), child: Text(member)));
                  }),
                ],
                onChanged: widget.isNight ? null : (value) {
                  setState(() { _selectedMembers[normalizedCardName] = value; });
                },
                underline: SizedBox(),
                icon: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.expand_more, color: Theme.of(context).colorScheme.primary.withOpacity(0.7)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
