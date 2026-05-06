import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../providers/sheets_provider.dart';
import 'service_report_result_screen.dart';

class ServiceReportScreen extends StatefulWidget {
  /// 他の人の報告として開く場合は true。氏名・ふりがな・グループを手入力可能にする
  final bool isOther;

  const ServiceReportScreen({super.key, this.isOther = false});

  @override
  State<ServiceReportScreen> createState() => _ServiceReportScreenState();
}

class _ServiceReportScreenState extends State<ServiceReportScreen> {
  

  static const List<String> _roles = ['伝道者', '補助開拓者', '正規開拓者'];

  late int _selectedMonth;
  String _selectedRole = '伝道者';
  String? _selectedGender;
  String? _selectedParticipation;
  final _hoursController = TextEditingController();
  final _bibleStudyController = TextEditingController();
  final _remarksController = TextEditingController();
  // 他の人の報告用
  final _nameController = TextEditingController();
  final _furiganaController = TextEditingController();
  String? _selectedGroup;
  List<String> _groupList = [];

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // デフォルト：現在の月の一つ前
    final now = DateTime.now();
    _selectedMonth = now.month == 1 ? 12 : now.month - 1;

    if (!widget.isOther) {
      final sheets = context.read<SheetsProvider>();
      if (sheets.currentUserRole == 'RP') {
        _selectedRole = '正規開拓者';
      }
      final g = sheets.currentUserGender;
      if (g == 'M') _selectedGender = '男性';
      if (g == 'F') _selectedGender = '女性';
    }

    if (widget.isOther) {
      _loadGroups();
    }
  }

  Future<void> _loadGroups() async {
    try {
      final names = await FirestoreService.getGroupNames();
      if (mounted) {
        setState(() {
          _groupList = names;
        });
      }
    } catch (e) {
      debugPrint('ServiceReportScreen: getGroupNames error: $e');
    }
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _bibleStudyController.dispose();
    _remarksController.dispose();
    _nameController.dispose();
    _furiganaController.dispose();
    super.dispose();
  }

  bool get _needsHours => _selectedRole != '伝道者';


  @override
  Widget build(BuildContext context) {
    final sheets = context.watch<SheetsProvider>();
    final userName = sheets.currentUserName ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isOther ? '奉仕報告（他の人）' : '奉仕報告'),
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 氏名
            _buildField(
              label: '氏名',
              required: true,
              child: widget.isOther
                  ? TextFormField(
                      controller: _nameController,
                      decoration: _inputDecoration('氏名を入力'),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        userName,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
            ),

            // ふりがな（他の人の報告のみ表示）
            if (widget.isOther)
              _buildField(
                label: 'ふりがな',
                required: true,
                child: TextFormField(
                  controller: _furiganaController,
                  decoration: _inputDecoration('ふりがなを入力'),
                ),
              ),

            // グループ名
            _buildField(
              label: 'グループ名',
              required: true,
              child: widget.isOther
                  ? _buildDropdown<String>(
                      value: _selectedGroup,
                      items: _groupList,
                      labelBuilder: (g) => g,
                      hint: '選択してください',
                      onChanged: (v) => setState(() => _selectedGroup = v),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        sheets.currentUserGroupName ?? '',
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
            ),

            // 性別（他の人の報告のみ表示）
            if (widget.isOther)
              _buildField(
                label: '性別',
                required: true,
                child: _buildDropdown<String>(
                  value: _selectedGender,
                  items: const ['男性', '女性'],
                  labelBuilder: (v) => v,
                  hint: '選択してください',
                  onChanged: (v) => setState(() => _selectedGender = v),
                ),
              ),

            // 立場
            _buildField(
              label: '立場',
              required: true,
              child: (!widget.isOther && sheets.currentUserRole == 'RP')
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: const Text(
                        '正規開拓者',
                        style: TextStyle(fontSize: 15),
                      ),
                    )
                  : _buildDropdown<String>(
                      value: _selectedRole,
                      items: _roles,
                      labelBuilder: (r) => r,
                      onChanged: (v) => setState(() {
                        _selectedRole = v!;
                        _hoursController.clear();
                        _selectedParticipation = null;
                      }),
                    ),
            ),

            // 月
            _buildField(
              label: '月',
              required: true,
              child: _buildDropdown<int>(
                value: _selectedMonth,
                items: List.generate(12, (i) => i + 1),
                labelBuilder: (m) => '$m月',
                onChanged: (v) => setState(() => _selectedMonth = v!),
              ),
            ),

            // 伝道者: はい/いいえ、それ以外: 時間
            if (_selectedRole == '伝道者') ...[
              _buildField(
                label: '伝道に参加しましたか',
                required: true,
                child: _buildDropdown<String>(
                  value: _selectedParticipation,
                  items: const ['はい', 'いいえ'],
                  labelBuilder: (v) => v,
                  hint: '選択してください',
                  onChanged: (v) =>
                      setState(() => _selectedParticipation = v),
                ),
              ),
            ] else ...[
              _buildField(
                label: '時間',
                required: true,
                child: TextFormField(
                  controller: _hoursController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _inputDecoration('時間を入力'),
                ),
              ),
            ],

            // 聖書研究
            _buildField(
              label: '聖書研究',
              required: true,
              child: TextFormField(
                controller: _bibleStudyController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _inputDecoration('数字を入力'),
              ),
            ),

            // 備考
            _buildField(
              label: '備考',
              child: TextFormField(
                controller: _remarksController,
                maxLines: 4,
                decoration: _inputDecoration('自由記入'),
              ),
            ),
            const SizedBox(height: 16),

            // 送信ボタン
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(Icons.send),
                label: Text(_isSubmitting ? '送信中...' : '送信する'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _isSubmitting ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required Widget child,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T? value,
    required List<T> items,
    required String Function(T) labelBuilder,
    required void Function(T?) onChanged,
    String? hint,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: hint != null
              ? Text(hint, style: TextStyle(color: Colors.grey.shade400))
              : null,
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(labelBuilder(item)),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
      ),
    );
  }

  Future<bool?> _showConfirmDialog({
    required String userName,
    required String furigana,
    required String groupName,
  }) {
    final isEvangelizer = _selectedRole == '伝道者';
    final entries = <MapEntry<String, String>>[
      MapEntry('氏名', userName),
      MapEntry('ふりがな', furigana),
      MapEntry('グループ名', groupName),
      MapEntry('性別', _selectedGender ?? ''),
      MapEntry('月', '$_selectedMonth月'),
      MapEntry('立場', _selectedRole),
      if (isEvangelizer)
        MapEntry('伝道に参加', _selectedParticipation ?? '')
      else
        MapEntry('時間', '${_hoursController.text.trim()}時間'),
      MapEntry('聖書研究', _bibleStudyController.text.trim().isEmpty
          ? '0'
          : _bibleStudyController.text.trim()),
      if (_remarksController.text.trim().isNotEmpty)
        MapEntry('備考', _remarksController.text.trim()),
    ];

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('送信内容の確認'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: entries
                  .map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 80,
                              child: Text(
                                e.key,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                e.value,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
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
              backgroundColor: Theme.of(context).colorScheme.primary,
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
    if (_isSubmitting) return;

    final sheets = context.read<SheetsProvider>();
    final String userName;
    final String furigana;
    final String groupName;
    if (widget.isOther) {
      userName = _nameController.text.trim();
      furigana = _furiganaController.text.trim();
      groupName = _selectedGroup ?? '';
      if (userName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('氏名を入力してください')),
        );
        return;
      }
      if (furigana.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ふりがなを入力してください')),
        );
        return;
      }
      if (groupName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('グループ名を選択してください')),
        );
        return;
      }
    } else {
      userName = sheets.currentUserName ?? '不明';
      furigana = sheets.currentUserFurigana ?? '';
      groupName = sheets.currentUserGroupName ?? '';
    }

    if (widget.isOther && _selectedGender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('性別を選択してください')),
      );
      return;
    }
    if (_selectedRole == '伝道者' && _selectedParticipation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('伝道に参加したか選択してください')),
      );
      return;
    }
    if (_needsHours && _hoursController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('時間を入力してください')),
      );
      return;
    }

    // 確認ダイアログ
    final confirmed = await _showConfirmDialog(
      userName: userName,
      furigana: furigana,
      groupName: groupName,
    );
    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    try {
      final isEvangelizer = _selectedRole == '伝道者';

      final success = await FirestoreService.submitPreachingReport(
        name: userName,
        furigana: furigana,
        groupName: groupName,
        gender: _selectedGender ?? '',
        month: _selectedMonth,
        role: _selectedRole,
        participation: isEvangelizer ? _selectedParticipation : null,
        hours: isEvangelizer
            ? null
            : int.tryParse(_hoursController.text.trim()),
        bibleStudy: int.tryParse(_bibleStudyController.text.trim()) ?? 0,
        remarks: _remarksController.text.trim(),
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('送信しました')),
          );
          // 入力欄をリセット
          setState(() {
            _bibleStudyController.clear();
            _remarksController.clear();
            _hoursController.clear();
            _selectedParticipation = null;
            _selectedGender = null;
            if (widget.isOther) {
              _nameController.clear();
              _furiganaController.clear();
              _selectedGroup = null;
            }
          });
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
                builder: (_) => const ServiceReportResultScreen()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('送信に失敗しました（APIエラー）')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラーが発生しました: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}
