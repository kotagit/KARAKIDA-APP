import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

class AdminGroupTerritoryAssignmentScreen extends StatefulWidget {
  final String title;
  /// 区域割当ての種別: 'NORMAL' / 'NIGHT' / 'AUTOLOCK'
  final String type;
  /// null の場合は GROUP_LIST から取得。指定された場合はその固定リストを使用
  final List<String>? fixedGroups;

  const AdminGroupTerritoryAssignmentScreen({
    super.key,
    this.title = 'グループ区域割当て',
    this.type = 'NORMAL',
    this.fixedGroups,
  });

  @override
  State<AdminGroupTerritoryAssignmentScreen> createState() =>
      _AdminGroupTerritoryAssignmentScreenState();
}

class _AdminGroupTerritoryAssignmentScreenState
    extends State<AdminGroupTerritoryAssignmentScreen> {
  

  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<String> _groups = [];
  List<String> _allTerritories = [];
  Map<String, String?> _currentAssignments = {}; // territoryNumber -> groupName (画面上の現在の選択状態)

  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final futures = <Future<dynamic>>[
        FirestoreService.getAllAreaIds(),
        FirestoreService.getAllLatestAssignments(type: widget.type),
      ];
      // fixedGroups が指定されていない場合のみ GROUP_LIST から取得
      if (widget.fixedGroups == null) {
        futures.add(FirestoreService.getGroupNames());
      }
      final results = await Future.wait(futures);
      final territories = results[0] as List<String>;
      final assignmentsMap = results[1] as Map<String, String>;
      final groups = widget.fixedGroups ?? (results[2] as List<String>);

      // 最新の日付も取得（任意の一件から）
      String? start;
      String? end;
      if (assignmentsMap.isNotEmpty) {
        final firstTerritory = assignmentsMap.keys.first;
        final group = assignmentsMap[firstTerritory];
        if (group != null) {
          final info = await FirestoreService.getLatestGroupAssignment(
            group,
            type: widget.type,
          );
          start = info.startDate;
          end = info.endDate;
        }
      }

      if (mounted) {
        setState(() {
          _groups = groups;
          _allTerritories = territories;
          _currentAssignments = assignmentsMap;
          if (start != null) _startDate = _parseDate(start);
          if (end != null) _endDate = _parseDate(end);
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

  DateTime? _parseDate(String dateStr) {
    try {
      final parts = dateStr.split('/');
      if (parts.length == 3) {
        return DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
      }
    } catch (_) {}
    return null;
  }


  String _formatDate(DateTime dt) {
    return '${dt.year}/${dt.month}/${dt.day}';
  }


  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_startDate ?? now)
        : (_endDate ?? _startDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('開始日付と終了日付を入力してください')),
      );
      return;
    }

    // 確認ダイアログで選択内容を表示
    final confirmed = await _showConfirmDialog();
    if (confirmed != true) return;

    setState(() => _saving = true);

    final success = await FirestoreService.saveAllGroupAssignments(
      assignments: _currentAssignments,
      startDate: _formatDate(_startDate!),
      endDate: _formatDate(_endDate!),
      type: widget.type,
    );

    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '全ての割当てを保存しました' : '保存に失敗しました'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
      if (success) {
        _load();
      }
    }
  }

  Future<bool?> _showConfirmDialog() {
    // グループごとに区域番号をまとめる
    final byGroup = <String, List<String>>{};
    _currentAssignments.forEach((territory, group) {
      if (group == null || group.isEmpty || group == '未割当て') return;
      byGroup.putIfAbsent(group, () => []).add(territory);
    });
    final sortedGroups = byGroup.keys.toList()..sort();
    for (final g in sortedGroups) {
      byGroup[g]!.sort((a, b) {
        final na = int.tryParse(a);
        final nb = int.tryParse(b);
        if (na != null && nb != null) return na.compareTo(nb);
        return a.compareTo(b);
      });
    }

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存内容の確認'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '期間: ${_formatDate(_startDate!)} 〜 ${_formatDate(_endDate!)}',
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                if (sortedGroups.isEmpty)
                  const Text('割当てなし（全ての区域がクリアされます）',
                      style: TextStyle(color: Colors.red))
                else
                  ...sortedGroups.map((g) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              g,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              byGroup[g]!.join(', '),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      )),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('戻る'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存する'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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
    return Column(
      children: [
        // 日付選択を最上部に固定
        Container(
          width: double.infinity,
          color: Colors.grey.shade50,
          padding: const EdgeInsets.all(16),
          child: _buildDateRow(),
        ),
        const Divider(height: 1),
        Expanded(
          child: _allTerritories.isEmpty 
            ? const Center(child: Text('区域データがありません'))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _allTerritories.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final territory = _allTerritories[index];
                  final assignedGroup = _currentAssignments[territory];

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 60,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            territory,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        const Icon(Icons.arrow_forward, color: Colors.grey, size: 16),
                        const SizedBox(width: 24),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: (_groups.contains(assignedGroup)) ? assignedGroup : '未割当て',
                              isExpanded: true,
                              items: [
                                const DropdownMenuItem(
                                  value: '未割当て',
                                  child: Text('未割当て', style: TextStyle(color: Colors.grey)),
                                ),
                                ..._groups.map((g) => DropdownMenuItem(
                                      value: g,
                                      child: Text(g),
                                    )),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _currentAssignments[territory] = val;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Icon(Icons.save),
                label: Text(_saving ? '保存中...' : '一括保存する'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _saving ? null : _save,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateRow() {
    return Row(
      children: [
        Expanded(child: _buildDateField(label: '開始日付', value: _startDate, isStart: true)),
        const SizedBox(width: 12),
        Expanded(child: _buildDateField(label: '終了日付', value: _endDate, isStart: false)),
      ],
    );
  }

  Widget _buildDateField({required String label, required DateTime? value, required bool isStart}) {
    return InkWell(
      onTap: () => _pickDate(isStart: isStart),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  const SizedBox(height: 2),
                  Text(
                    value != null ? _formatDate(value) : '未設定',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


}
