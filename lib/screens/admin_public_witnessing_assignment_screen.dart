import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

class AdminPublicWitnessingAssignmentScreen extends StatefulWidget {
  final String date;
  final String startTime;
  final String place;
  final List<String> conductorApplicants;
  final List<String> allApplicants;
  final List<String> subLocations;
  final String slotKey;
  final Map<String, Map<String, dynamic>> initialAssignments;

  const AdminPublicWitnessingAssignmentScreen({
    super.key,
    required this.date,
    required this.startTime,
    required this.place,
    required this.conductorApplicants,
    required this.allApplicants,
    required this.subLocations,
    required this.slotKey,
    required this.initialAssignments,
  });

  @override
  State<AdminPublicWitnessingAssignmentScreen> createState() =>
      _AdminPublicWitnessingAssignmentScreenState();
}

class _AdminPublicWitnessingAssignmentScreenState
    extends State<AdminPublicWitnessingAssignmentScreen> {
  static const Color _primaryBlue = Color(0xFF047CBC);
  late Map<String, Map<String, dynamic>> _assignments;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // 初期データのディープコピー（型変換を安全に行う）
    _assignments = {};
    for (final subName in widget.subLocations) {
      final data = widget.initialAssignments[subName] ?? {};
      final List<dynamic> rawParticipants = data['参加者'] is List ? data['参加者'] : [];
      final List<String?> participants = List<String?>.from(rawParticipants);
      while (participants.length < 5) {
        participants.add(null);
      }
      
      _assignments[subName] = {
        '司会者': data['司会者'] as String?,
        '参加者': participants.take(5).toList(),
      };
    }
  }

  Future<void> _saveAll() async {
    setState(() => _saving = true);
    try {
      bool allSuccess = true;
      final datePart = widget.date.split('(')[0];

      for (final subName in widget.subLocations) {
        final assignment = _assignments[subName];
        if (assignment == null) continue;

        final docId = '${datePart}_${widget.startTime}_$subName';
        final success = await FirestoreService.savePublicWitnessingAssignment(
          docId,
          {
            'date': widget.date,
            'time': widget.startTime,
            'place': subName,
            'assignments': {
              '司会者': assignment['司会者'],
              '参加者': assignment['参加者'],
            },
          },
        );
        if (!success) allSuccess = false;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(allSuccess ? '保存しました' : '保存に失敗しました'),
            backgroundColor: allSuccess ? Colors.green : Colors.red,
          ),
        );
        if (allSuccess) Navigator.pop(context, true); // 成功したら戻る
      }
    } catch (e) {
      debugPrint('Save Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Set<String> _getAllAssigned() {
    final Set<String> assigned = {};
    for (final data in _assignments.values) {
      final cond = data['司会者'] as String?;
      if (cond != null) assigned.add(cond);
      final parts = List<String?>.from(data['参加者'] ?? []);
      for (final p in parts) {
        if (p != null) assigned.add(p);
      }
    }
    return assigned;
  }

  @override
  Widget build(BuildContext context) {
    final allAssigned = _getAllAssigned();

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text('${widget.date} ${widget.startTime} 策定'),
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.save, color: Colors.white),
            label: const Text('保存', style: TextStyle(color: Colors.white)),
            onPressed: _saving ? null : _saveAll,
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: widget.subLocations.length,
        itemBuilder: (context, index) {
          final subName = widget.subLocations[index];
          return _buildSubLocationSection(subName, allAssigned);
        },
      ),
    );
  }

  Widget _buildSubLocationSection(String subName, Set<String> allAssigned) {
    final assignment = _assignments[subName]!;
    final conductor = assignment['司会者'] as String?;
    final participants = List<String?>.from(assignment['参加者'] ?? []);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Text(
                  subName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildAssignmentRow(
                  label: '司会者',
                  value: conductor,
                  applicants: widget.conductorApplicants,
                  allAssigned: allAssigned,
                  onChanged: (val) {
                    setState(() => _assignments[subName]!['司会者'] = val);
                  },
                ),
                const Divider(height: 32),
                ...List.generate(participants.length, (idx) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildAssignmentRow(
                      label: '参加者 ${idx + 1}',
                      value: participants[idx],
                      applicants: widget.allApplicants,
                      allAssigned: allAssigned,
                      onChanged: (val) {
                        setState(() {
                          final list = List<String?>.from(_assignments[subName]!['参加者']);
                          list[idx] = val;
                          _assignments[subName]!['参加者'] = list;
                        });
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentRow({
    required String label,
    required String? value,
    required List<String> applicants,
    required Set<String> allAssigned,
    required ValueChanged<String?> onChanged,
  }) {
    // 他の枠ですでに選ばれている人を除外
    final filteredApplicants = applicants.where((name) {
      if (name == value) return true; // 自分自身は常に表示
      return !allAssigned.contains(name);
    }).toList();

    // 現在選択されている名前が applicants にない場合でも表示できるようにする
    final List<String?> dropdownItems = [null];
    if (value != null && !filteredApplicants.contains(value)) {
      dropdownItems.add(value);
    }
    dropdownItems.addAll(filteredApplicants);

    return Row(
      children: [
        SizedBox(
          width: 85,
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: value,
                isExpanded: true,
                hint: const Text('未選択', style: TextStyle(fontSize: 14)),
                items: dropdownItems.map((name) {
                  return DropdownMenuItem<String?>(
                    value: name,
                    child: Text(name ?? '未選択', style: const TextStyle(fontSize: 14)),
                  );
                }).toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
