import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../providers/sheets_provider.dart';
import '../services/firestore_service.dart';
import 'application_result_screen.dart';

class ApplicationScreen extends StatefulWidget {
  const ApplicationScreen({super.key});

  @override
  State<ApplicationScreen> createState() => _ApplicationScreenState();
}

class _ApplicationScreenState extends State<ApplicationScreen> {
  static const Color _primaryBlue = Color(0xFF047CBC);

  bool _loading = true;
  String? _error;

  // 選択中の選択肢キー: item.key
  final Set<String> _selectedKeys = {};

  // 各パネルの役割選択: key → 選択された役割
  final Map<String, String> _selectedRoles = {};

  static const List<String> _roles = [
    '参加者',
    '司会者（カート有）',
    'カート運搬車',
    '司会者（カート無）',
  ];

  // パース済み選択肢リスト
  List<_SelectableItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final docs = await FirestoreService.getPublicWitnessingOptions();

      final items = <_SelectableItem>[];
      for (final d in docs) {
        final day = (d['day'] ?? '').toString();
        final dayofweek = (d['dayofweek'] ?? '').toString();
        final starttime = (d['starttime'] ?? '').toString();
        final endtime = (d['endtime'] ?? '').toString();
        final place = (d['place'] ?? '').toString();
        if (day.isEmpty && place.isEmpty) continue;
        items.add(_SelectableItem(
          key: d['id']?.toString() ?? '${day}_${starttime}_$place',
          date: day,
          weekday: dayofweek,
          startTime: starttime,
          endTime: endtime,
          place: place,
        ));
      }

      if (mounted) {
        setState(() {
          _items = items;
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

  Future<bool?> _showConfirmDialog() {
    final selectedItems = _items.where((i) => _selectedKeys.contains(i.key)).toList()
      ..sort((a, b) {
        final c = a.date.compareTo(b.date);
        if (c != 0) return c;
        return a.startTime.compareTo(b.startTime);
      });

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('送信内容の確認 (${selectedItems.length}件)'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: selectedItems.map((item) {
                final role = _selectedRoles[item.key] ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.date} (${item.weekday}) ${item.startTime}〜${item.endTime}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _primaryBlue,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.place}  /  $role',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('修正する'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('送信する'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (_selectedKeys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('申込む項目を選択してください')),
      );
      return;
    }

    final missingRole = _selectedKeys.any((k) => !_selectedRoles.containsKey(k));
    if (missingRole) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('すべての項目で役割を選択してください')),
      );
      return;
    }

    // 確認ダイアログ
    final confirmed = await _showConfirmDialog();
    if (confirmed != true) return;

    setState(() => _loading = true);

    final sheets = context.read<SheetsProvider>();
    final userName = sheets.currentUserName ?? '不明';

    try {
      bool allSuccess = true;

      for (final item in _items.where((i) => _selectedKeys.contains(i.key))) {
        final role = _selectedRoles[item.key] ?? '';
        final success = await FirestoreService.submitPublicWitnessing(
          name: userName,
          day: item.date,
          dayofweek: item.weekday,
          starttime: item.startTime,
          endtime: item.endTime,
          place: item.place,
          role: role,
        );
        if (!success) allSuccess = false;
      }

      if (mounted) {
        setState(() {
          _loading = false;
          if (allSuccess) {
            _selectedKeys.clear();
            _selectedRoles.clear();
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(allSuccess ? '送信しました' : '一部の送信に失敗しました'),
            backgroundColor: allSuccess ? Colors.green : Colors.red,
          ),
        );

        if (allSuccess) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
                builder: (_) => const ApplicationResultScreen()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('送信に失敗しました: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('申請'),
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.red)))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('データがありません'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() => _loading = true);
                _load();
              },
              child: const Text('再読み込み'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: ListView.separated(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            itemCount: _items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) =>
                _buildItemCard(_items[index]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.send),
              label: Text(
                _selectedKeys.isEmpty
                    ? '送信する'
                    : '送信する（${_selectedKeys.length}件）',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,
                foregroundColor: Colors.white,
              ),
              onPressed: _submit,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 36),
          _headerCell('日付'),
          _headerCell('曜日'),
          _headerCell('時間'),
          _headerCell('場所'),
        ],
      ),
    );
  }

  Widget _headerCell(String text) {
    return Expanded(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: _primaryBlue,
        ),
      ),
    );
  }

  /// 場所名から背景色を決定する
  Color _colorForPlace(String place) {
    if (place.contains('唐木田')) {
      return const Color(0xFF90EE90); // 黄緑
    } else if (place.contains('堀之内')) {
      return const Color(0xFF87CEEB); // 青系（スカイブルー）
    }
    return Colors.grey.shade200;
  }

  Widget _buildItemCard(_SelectableItem item) {
    final isSelected = _selectedKeys.contains(item.key);
    final placeColor = _colorForPlace(item.place);
    final selectedRole = _selectedRoles[item.key];

    return GestureDetector(
      onTap: () => setState(() {
        if (_selectedKeys.contains(item.key)) {
          _selectedKeys.remove(item.key);
          _selectedRoles.remove(item.key);
        } else {
          _selectedKeys.add(item.key);
        }
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? _primaryBlue : Colors.grey.shade300,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? _primaryBlue.withOpacity(0.10)
                  : Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Icon(
                    isSelected
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
                    color: isSelected ? _primaryBlue : Colors.grey.shade400,
                    size: 22,
                  ),
                ),
                Expanded(
                  child: Text(
                    item.date,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    item.weekday,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: (item.weekday == '土' || item.weekday == '日')
                          ? Colors.red
                          : Colors.black87,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    item.startTime,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(
                        vertical: 4, horizontal: 6),
                    decoration: BoxDecoration(
                      color: placeColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.place,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (isSelected) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Column(
                children: _roles.map((role) {
                  final isRoleSelected = selectedRole == role;
                  return InkWell(
                    onTap: () => setState(() {
                      _selectedRoles[item.key] = role;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(
                            isRoleSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 20,
                            color: isRoleSelected ? _primaryBlue : Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            role,
                            style: TextStyle(
                              fontSize: 14,
                              color: isRoleSelected ? _primaryBlue : Colors.black87,
                              fontWeight: isRoleSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SelectableItem {
  final String key;
  final String date;
  final String weekday;
  final String startTime;
  final String endTime;
  final String place;

  const _SelectableItem({
    required this.key,
    required this.date,
    required this.weekday,
    required this.startTime,
    required this.endTime,
    required this.place,
  });
}
