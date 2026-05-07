import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../providers/sheets_provider.dart';
import '../services/firestore_service.dart';

class SheetViewScreen extends StatefulWidget {
  final bool isNight;
  final bool isAutolock;
  final String? assignedMemberName;
  final String? displayTitle;
  const SheetViewScreen({super.key, this.isNight = false, this.isAutolock = false, this.assignedMemberName, this.displayTitle});

  @override
  State<SheetViewScreen> createState() => _SheetViewScreenState();
}

class _SheetViewScreenState extends State<SheetViewScreen> {
  final ScrollController _mainScrollController = ScrollController();
  final ScrollController _historyScrollController = ScrollController();
  bool _syncing = false;
  bool _showHistory = false;
  List<Map<String, dynamic>> _statusOptions = [];

  static const double _sectionRowHeight = 32.0;
  static const double _dataRowHeight = 60.0;
  static const double _autolockRowHeight = 44.0;
  static const double _historyDateHeaderHeight = 40.0;

  @override
  void initState() {
    super.initState();
    _mainScrollController.addListener(_syncMainToHistory);
    _historyScrollController.addListener(_syncHistoryToMain);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SheetsProvider>().startListening();
      if (widget.isAutolock) {
        _checkRecentAutolockEditors();
      }
    });
    _loadStatusOptions();
  }

  Future<void> _loadStatusOptions() async {
    try {
      final opts = await FirestoreService.getVisitStatusOptions();
      if (mounted) setState(() => _statusOptions = opts);
    } catch (_) {}
  }

  Future<void> _checkRecentAutolockEditors() async {
    final sheets = context.read<SheetsProvider>();
    // カードデータ＋編集者チェック完了を待つ
    await Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return false;
      final p = context.read<SheetsProvider>();
      return p.isLoading || p.isCheckingEditors;
    });
    if (!mounted) return;

    final editors = context.read<SheetsProvider>().recentAutolockEditors;
    if (editors.isEmpty) return;

    // スタッフ名と記録時刻を整理（重複除去）
    final seen = <String>{};
    final lines = <String>[];
    for (final e in editors) {
      final name = e['staffName'] as String? ?? '';
      if (seen.add(name)) lines.add(name);
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('警告'),
          ],
        ),
        content: const Text(
          '直近10分以内に別の方がこの物件を訪問しました。',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('戻る'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<SheetsProvider>().clearRecentAutolockEditors();
              Navigator.pop(ctx);
            },
            child: const Text('理解しました'),
          ),
        ],
      ),
    );
  }

  void _syncMainToHistory() {
    if (_syncing) return;
    _syncing = true;
    if (_historyScrollController.hasClients) {
      _historyScrollController.jumpTo(_mainScrollController.offset);
    }
    _syncing = false;
  }

  void _syncHistoryToMain() {
    if (_syncing) return;
    _syncing = true;
    if (_mainScrollController.hasClients) {
      _mainScrollController.jumpTo(_historyScrollController.offset);
    }
    _syncing = false;
  }

  @override
  void dispose() {
    _mainScrollController.removeListener(_syncMainToHistory);
    _historyScrollController.removeListener(_syncHistoryToMain);
    _mainScrollController.dispose();
    _historyScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sheets = context.watch<SheetsProvider>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isAutolock
              ? (widget.displayTitle ?? sheets.selectedCardName ?? '')
              : '区域No.${sheets.selectedCardName ?? ''}',
        ),
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            sheets.stopListening();
            Navigator.pop(context);
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (sheets.selectedCardName != null) {
                if (widget.isAutolock) {
                  sheets.selectAutolockCard(sheets.selectedCardName!);
                } else {
                  sheets.selectCard(sheets.selectedCardName!);
                }
              }
            },
          ),
        ],
      ),
      body: _buildBody(sheets),
    );
  }

  Widget _buildBody(SheetsProvider sheets) {
    if (sheets.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (sheets.error != null) {
      return Center(
        child: Text(sheets.error!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (sheets.cardAddresses.isEmpty) {
      return const Center(child: Text('データがありません'));
    }

    return _buildCardView(sheets);
  }

  Widget _buildCardView(SheetsProvider sheets) {
    final addresses = sheets.cardAddresses;
    final visitId = widget.isNight
        ? (sheets.nightStartDate != null && sheets.nightEndDate != null
            ? '${sheets.nightStartDate}_${sheets.nightEndDate}'
            : null)
        : (sheets.visitStartDate != null && sheets.visitEndDate != null
            ? '${sheets.visitStartDate}_${sheets.visitEndDate}'
            : null);

    // 建物名（townName）ごとにグループ化
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final addr in addresses) {
      final town = addr['townName'] as String? ?? '';
      groups.putIfAbsent(town, () => []);
      groups[town]!.add(addr);
    }

    // フラットなリストアイテムを構築（セクション見出し＋住所行）
    final items = <_ListItem>[];
    for (final entry in groups.entries) {
      if (entry.key.isNotEmpty) {
        items.add(_ListItem(type: _ItemType.section, label: entry.key, data: entry.value.first));
      }
      for (final addr in entry.value) {
        items.add(_ListItem(type: _ItemType.address, data: addr));
      }
    }

    // 履歴ヘッダー用の日付リストを取得
    List<String> historyStartDates = [];
    for (final item in items) {
      if (item.type == _ItemType.address) {
        final visits = item.data['visits'] as List<Map<String, dynamic>>? ?? [];
        final hist = widget.isNight
            ? visits.take(4).toList()
            : (visits.length > 1
                ? visits.sublist(1, visits.length > 5 ? 5 : visits.length)
                : <Map<String, dynamic>>[]);
        if (hist.isNotEmpty) {
          historyStartDates = hist
              .map((v) => v['startDate'] as String? ?? '')
              .where((s) => s.isNotEmpty)
              .toList();
          break;
        }
      }
    }

    return Column(
      children: [
        _buildHeaderInfo(sheets),
        const Divider(height: 1),
        Expanded(
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.only(top: _showHistory ? _historyDateHeaderHeight + 1 : 0.0),
                child: ListView.builder(
                  controller: _mainScrollController,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    if (item.type == _ItemType.section) {
                      final mapLink = item.data['mapLink'] as String?;
                      return SizedBox(
                        height: _sectionRowHeight,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                          child: Row(
                            children: [
                              if (mapLink != null && mapLink.isNotEmpty)
                                GestureDetector(
                                  onTap: () => _openLink(mapLink),
                                  child: Padding(
                                    padding: EdgeInsets.only(right: 6),
                                    child: Icon(Icons.location_on, color: Theme.of(context).colorScheme.secondary, size: 20),
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  item.label!,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Theme.of(context).colorScheme.tertiary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return SizedBox(
                      height: widget.isAutolock ? _autolockRowHeight : _dataRowHeight,
                      child: _buildPersonRow(sheets, item.data, visitId),
                    );
                  },
                ),
              ),
              // 暗幕
              if (_showHistory)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => _showHistory = false),
                    child: Container(color: Colors.black26),
                  ),
                ),
              // 履歴パネル
              if (_showHistory)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: MediaQuery.of(context).size.width * 0.75,
                  child: Material(
                    elevation: 8,
                    child: Container(
                      color: Colors.white,
                      child: Column(
                        children: [
                          // 日付ヘッダー行
                          SizedBox(
                            height: _historyDateHeaderHeight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              color: Colors.grey.shade100,
                              child: Row(
                                children: [
                                  const SizedBox(width: 36),
                                  // 各履歴列に日付を表示
                                  ...List.generate(4, (i) {
                                    final date = i < historyStartDates.length
                                        ? historyStartDates[i]
                                        : '';
                                    final parts = date.split('/');
                                    final year = parts.isNotEmpty ? parts[0] : '';
                                    final monthDay = parts.length >= 3
                                        ? '${parts[1]}/${parts[2]}'
                                        : '';
                                    return Expanded(
                                      child: date.isEmpty
                                          ? const SizedBox()
                                          : Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  year,
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                  textAlign: TextAlign.center,
                                                ),
                                                Text(
                                                  monthDay,
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ],
                                            ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView.builder(
                              controller: _historyScrollController,
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final item = items[index];
                                if (item.type == _ItemType.section) {
                                  return SizedBox(
                                    height: _sectionRowHeight,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                                      child: Text(
                                        item.label!,
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Theme.of(context).colorScheme.tertiary),
                                      ),
                                    ),
                                  );
                                }
                                return SizedBox(
                                  height: widget.isAutolock ? _autolockRowHeight : _dataRowHeight,
                                  child: _buildHistoryRow(item.data),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      String cleanDate = dateStr;
      if (dateStr.contains('T')) cleanDate = dateStr.split('T')[0];
      final parts = cleanDate.split(RegExp(r'[/\-]'));
      if (parts.length == 3) {
        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final day = int.parse(parts[2]);
        // タイムゾーンによるずれを防ぐため、UTCとしてDateTimeを作成する
        final dt = DateTime.utc(year, month, day);
        const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
        final weekday = weekdays[dt.weekday - 1];
        return '$year年$month月${day}日（$weekday）';
      }
    } catch (_) {}
    return dateStr;
  }

  Widget _buildHeaderInfo(SheetsProvider sheets) {
    final startStr = _formatDate(widget.isNight ? sheets.nightStartDate : sheets.visitStartDate);
    final endStr = _formatDate(widget.isNight ? sheets.nightEndDate : sheets.visitEndDate);
    final userName = widget.assignedMemberName ?? sheets.currentUserName ?? '';

    return Container(
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (userName.isNotEmpty)
                  Text('担当者：$userName', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                if (startStr.isNotEmpty)
                  Text('開始日付：$startStr', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                if (endStr.isNotEmpty)
                  Text('終了日付：$endStr', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ],
            ),
          ),
          ElevatedButton.icon(
            icon: Icon(_showHistory ? Icons.visibility_off : Icons.history, size: 18),
            label: const Text('履歴', style: TextStyle(fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _showHistory ? Theme.of(context).colorScheme.secondary : Colors.white,
              foregroundColor: _showHistory ? Colors.white : Theme.of(context).colorScheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => setState(() => _showHistory = !_showHistory),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    final opt = _statusOptions.cast<Map<String, dynamic>?>().firstWhere(
      (o) => o!['label'] == status,
      orElse: () => null,
    );
    final hex = opt?['color'] as String?;
    if (hex != null && hex.isNotEmpty) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    return Colors.transparent;
  }

  Future<void> _openLink(String url) async {
    try {
      final match = RegExp(r'geo:(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(url);
      final Uri uri;
      if (match != null) {
        final lat = match.group(1);
        final lng = match.group(2);
        uri = Platform.isAndroid
            ? Uri.parse('geo:$lat,$lng?z=17')
            : Uri.parse('https://maps.apple.com/?ll=$lat,$lng&z=17');
      } else {
        uri = Uri.parse(url);
      }
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[Link] openUrl error: $e');
    }
  }

  /// 現在の訪問期間のステータスを取得
  String _getCurrentStatus(Map<String, dynamic> addr, String? visitId) {
    if (visitId == null) return '';
    final visits = addr['visits'] as List<Map<String, dynamic>>? ?? [];
    for (final v in visits) {
      if (v['id'] == visitId) {
        return v['statusResult'] as String? ?? '';
      }
    }
    final current = addr['currentVisit'] as Map<String, dynamic>?;
    if (current != null) return current['statusResult'] as String? ?? '';
    return '';
  }

  Widget _buildPersonRow(SheetsProvider sheets, Map<String, dynamic> addr, String? visitId) {
    final no = addr['addressNumber']?.toString() ?? '';
    final houseType = addr['houseType'] as String? ?? '';
    final buildName = addr['buildName'] as String? ?? '';
    final roomNum = addr['roomNum'] as String? ?? '';
    final chome = addr['chome']?.toString() ?? '';
    final gaiku = addr['gaiku']?.toString() ?? '';
    final townName = addr['townName'] as String? ?? '';
    const String displayNo = '';
    final townChome = townName + chome;
    final rawLabel = widget.isAutolock
        ? no
        : [townChome, gaiku, no].where((s) => s.isNotEmpty).join('-');
    final houseName = addr['targetName'] as String? ?? '';
    final displayLabel = houseName.isNotEmpty ? '$rawLabel（$houseName）' : rawLabel;
    final status = _getCurrentStatus(addr, visitId);
    final mapLink = addr['mapLink'] as String?;
    final color = addr['color'] as int?;

    // 色の変換
    const sheetToAppColor = <int, Color>{
      0xFF38761d: Color(0xFF6d9eeb),
      0xFF6aa84f: Color(0xFF6d9eeb),
    };
    final bgColor = color != null
        ? (sheetToAppColor[color] ?? Color(color))
        : _statusColor(status);

    return Container(
      decoration: BoxDecoration(
        color: bgColor == Colors.transparent ? null : bgColor,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mapLink != null && mapLink.isNotEmpty)
              GestureDetector(
                onTap: () => _openLink(mapLink),
                child: Padding(
                  padding: EdgeInsets.only(left: 6, right: 4),
                  child: Icon(Icons.location_on, color: Theme.of(context).colorScheme.secondary, size: 26),
                ),
              )
            else
              const SizedBox(width: 36),
            if (displayNo.isNotEmpty)
              SizedBox(
                width: 40,
                child: Text(displayNo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.center),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (buildName.isNotEmpty)
                    Text(buildName, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: rawLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      if (houseName.isNotEmpty)
                        TextSpan(text: '（$houseName）', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal)),
                    ]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (bgColor != const Color(0xFF6d9eeb))
              GestureDetector(
                onTap: () => _showEditDialog(context, sheets, addr, status),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (status.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 20),
                        child: Text(
                          status,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                      ),
                    Container(
                      width: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '入力',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryRow(Map<String, dynamic> addr) {
    final no = addr['addressNumber']?.toString() ?? '';
    final visits = addr['visits'] as List<Map<String, dynamic>>? ?? [];
    // 夜間カード: index 0 からそのまま4件表示（すべて過去履歴）
    // 通常カード: index 0 は現在期間なのでスキップして4件表示
    final List<Map<String, dynamic>> history;
    if (widget.isNight) {
      history = visits.take(4).toList();
    } else {
      history = visits.length > 1 ? visits.sublist(1, visits.length > 5 ? 5 : visits.length) : [];
    }

    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          SizedBox(width: 36, child: Text(no, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
          ...history.map((v) {
            final status = v['statusResult'] as String? ?? '';
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: _statusColor(status),
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(status, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
              ),
            );
          }),
          // 空の列で埋める
          ...List.generate(
            (4 - history.length).clamp(0, 4),
            (_) => Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('', textAlign: TextAlign.center, style: TextStyle(fontSize: 11)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    SheetsProvider sheets,
    Map<String, dynamic> addr,
    String currentValue,
  ) {
    final addressId = addr['id'] as String;
    final uid = addr['uid'] as String? ?? addressId;
    String? selected = currentValue.isEmpty ? null : currentValue;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ..._statusOptions.map((opt) {
                final label = opt['label'] as String;
                final isSelected = selected == label;
                return ListTile(
                  title: Text(label),
                  selected: isSelected,
                  selectedTileColor: Colors.blue.withValues(alpha: 0.1),
                  trailing: isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
                  onTap: () => setState(() => selected = label),
                );
              }),
              ListTile(
                title: const Text('クリア', style: TextStyle(color: Colors.grey)),
                selected: selected == null || selected == '',
                selectedTileColor: Colors.blue.withValues(alpha: 0.1),
                trailing: (selected == null || selected == '')
                    ? const Icon(Icons.check, color: Colors.blue)
                    : null,
                onTap: () => setState(() => selected = ''),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () {
                final value = selected ?? '';
                if (widget.isAutolock) {
                  sheets.updateAutolockVisitStatus(uid, value);
                } else if (widget.isNight) {
                  sheets.updateNightVisitStatus(addressId, value);
                } else {
                  sheets.updateVisitStatus(addressId, value);
                }
                _notifyIfRJ(value, sheets, addressId);
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _notifyIfRJ(String value, SheetsProvider sheets, String addressId) {
    if (value.toUpperCase() == 'RJ') {
      final userName = sheets.currentUserName ?? '不明';
      final cardName = sheets.selectedCardName ?? '';
      FirestoreService.notifyAdmin(
        type: 'reject',
        message: '$userNameさんがカード $cardName の住所 $addressId を拒否(RJ)に設定しました',
        fromUser: userName,
        extra: {
          'cardName': cardName,
          'addressId': addressId,
          'status': value,
        },
      );
    }
  }

  Widget _quickButton(
    BuildContext ctx,
    SheetsProvider sheets,
    String addressId,
    TextEditingController controller,
    String value, {
    String? hex,
    String? uid,
  }) {
    Color bgColor = Colors.grey.shade200;
    if (hex != null && hex.isNotEmpty) {
      bgColor = Color(int.parse('FF$hex', radix: 16));
    }
    return ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: bgColor),
      onPressed: () {
        if (widget.isAutolock) {
          sheets.updateAutolockVisitStatus(uid ?? addressId, value);
        } else if (widget.isNight) {
          sheets.updateNightVisitStatus(addressId, value);
        } else {
          sheets.updateVisitStatus(addressId, value);
        }
        _notifyIfRJ(value, sheets, addressId);
        Navigator.pop(ctx);
      },
      child: Text(value.isEmpty ? 'クリア' : value),
    );
  }
}

enum _ItemType { section, address }

class _ListItem {
  final _ItemType type;
  final String? label;
  final Map<String, dynamic> data;

  _ListItem({required this.type, this.label, required this.data});
}
