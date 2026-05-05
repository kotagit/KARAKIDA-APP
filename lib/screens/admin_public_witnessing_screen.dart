import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import 'admin_public_witnessing_assignment_screen.dart';

class AdminPublicWitnessingScreen extends StatefulWidget {
  const AdminPublicWitnessingScreen({super.key});

  @override
  State<AdminPublicWitnessingScreen> createState() =>
      _AdminPublicWitnessingScreenState();
}

class _AdminPublicWitnessingScreenState
    extends State<AdminPublicWitnessingScreen> {
  static const Color _primaryBlue = Color(0xFF047CBC);

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<_SlotItem> _slots = [];

  // slotKey -> { subLocation -> { '司会者': 'name', '参加者': ['name', ...] } }
  Map<String, Map<String, Map<String, dynamic>>> _assignmentsMap = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  // 場所に応じたサブログ名（フルネーム）を取得
  List<String> _getFullPlaceNames(String weekday, String time, String place) {
    if (place.contains('唐木田')) {
      return ['唐木田駅構内'];
    }
    if (place.contains('堀之内')) {
      final base = '堀之内駅';
      if (weekday == '水' && time == '18:00') {
        return ['${base}三和前', '${base}FM前'];
      }
      return ['${base}三和前', '${base}FM前', '${base}信号前'];
    }
    return [place];
  }

  Future<void> _load() async {
    try {
      // 1. 募集項目 (スロット) を取得
      final options = await FirestoreService.getPublicWitnessingOptions();

      // 2. 全申込みを取得
      final allApps = await FirestoreService.getAllPublicWitnessing();

      // 3. 既存の全割当てを取得
      final allAssignments = await FirestoreService.getAllPublicWitnessingAssignments();
      // docId -> data
      final Map<String, Map<String, dynamic>> existingDocs = {};
      for (final doc in allAssignments) {
        existingDocs[doc['id'] as String] = doc;
      }

      final List<_SlotItem> loadedSlots = [];
      final Map<String, Map<String, Map<String, dynamic>>> newAssignmentsMap = {};

      for (final opt in options) {
        final dateStr = (opt['day'] ?? '').toString();
        final weekday = (opt['dayofweek'] ?? '').toString();
        final dateWithDay = '$dateStr($weekday)'; // 5/8(水) 形式
        final startTime = (opt['starttime'] ?? '').toString();
        final placeBase = (opt['place'] ?? '').toString();

        final fullPlaces = _getFullPlaceNames(weekday, startTime, placeBase);
        final slotKey = '${dateStr}_${startTime}_$placeBase'; // 内部管理用キー

        // このスロットに対する申込みを抽出
        final applicantsForSlot = allApps.where((app) {
          return app['day'] == dateStr &&
              app['dayofweek'] == weekday &&
              app['starttime'] == startTime &&
              app['place'] == placeBase;
        }).toList();

        // 司会者として申し込んだ人
        final conductorApplicants = applicantsForSlot
            .where((app) => (app['role'] ?? '').toString().contains('司会者'))
            .map((app) => (app['name'] ?? '').toString())
            .toSet()
            .toList();
        conductorApplicants.sort();

        // 全ての申込者（参加者用）
        final allApplicants = applicantsForSlot
            .map((app) => (app['name'] ?? '').toString())
            .toSet()
            .toList();
        allApplicants.sort();

        final Map<String, Map<String, dynamic>> subMap = {};

        for (final fullPlace in fullPlaces) {
          final docId = '${dateStr}_${startTime}_$fullPlace';
          
          if (existingDocs.containsKey(docId)) {
            final docData = existingDocs[docId]!;
            final ass = docData['assignments'] as Map<String, dynamic>? ?? {};
            subMap[fullPlace] = {
              '司会者': ass['司会者'],
              '参加者': List<String?>.from(ass['参加者'] ?? List.filled(5, null)),
            };
          } else {
            subMap[fullPlace] = {
              '司会者': null,
              '参加者': List<String?>.filled(5, null),
            };
          }
        }
        
        newAssignmentsMap[slotKey] = subMap;

        loadedSlots.add(_SlotItem(
          date: dateWithDay,
          weekday: weekday,
          startTime: startTime,
          place: placeBase,
          conductorApplicants: conductorApplicants,
          allApplicants: allApplicants,
          subLocations: fullPlaces,
          slotKey: slotKey,
        ));
      }

      if (mounted) {
        setState(() {
          _slots = loadedSlots;
          _assignmentsMap = newAssignmentsMap;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('AdminPublicWitnessingScreen load error: $e');
      if (mounted) {
        setState(() {
          _error = '読み込みに失敗しました: $e';
          _loading = false;
        });
      }
    }
  }

  // _save は AdminPublicWitnessingAssignmentScreen に移動したため削除しました


  Color _colorForPlace(String place) {
    if (place.contains('唐木田')) return const Color(0xFF90EE90);
    if (place.contains('堀之内')) return const Color(0xFF87CEEB);
    return Colors.grey.shade200;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('公共エリア 策定'),
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_slots.isEmpty) {
      return const Center(child: Text('募集項目がありません', style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _slots.length,
      itemBuilder: (context, index) {
        final slot = _slots[index];
        // 前の項目と日付が異なる場合に隙間を作る
        final bool isNewDay = index == 0 || _slots[index - 1].date != slot.date;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isNewDay && index > 0) const SizedBox(height: 28), // 日付の変わり目に大きな隙間
            if (isNewDay)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: _buildSectionTag(slot.date),
              ),
            _buildSlotCard(slot),
          ],
        );
      },
    );
  }

  Widget _buildSectionTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _primaryBlue,
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
    );
  }

  Widget _buildSlotCard(_SlotItem slot) {
    final placeColor = _colorForPlace(slot.place);
    final subMap = _assignmentsMap[slot.slotKey] ?? {};

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AdminPublicWitnessingAssignmentScreen(
              date: slot.date,
              startTime: slot.startTime,
              place: slot.place,
              conductorApplicants: slot.conductorApplicants,
              allApplicants: slot.allApplicants,
              subLocations: slot.subLocations,
              slotKey: slot.slotKey,
              initialAssignments: subMap,
            ),
          ),
        ).then((_) => _load()); // 戻ってきた時に再読み込み
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300, width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const SizedBox(
              width: 36,
              child: Icon(
                Icons.access_time,
                color: _primaryBlue,
                size: 22,
              ),
            ),
            Expanded(
              child: Text(
                slot.startTime,
                textAlign: TextAlign.left,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
              decoration: BoxDecoration(
                color: placeColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                slot.place,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  // 割当て行の構築ロジックは AssignmentScreen に移動したため削除
}

class _SlotItem {
  final String date;
  final String weekday;
  final String startTime;
  final String place;
  final List<String> conductorApplicants;
  final List<String> allApplicants;
  final List<String> subLocations;
  final String slotKey;

  _SlotItem({
    required this.date,
    required this.weekday,
    required this.startTime,
    required this.place,
    required this.conductorApplicants,
    required this.allApplicants,
    required this.subLocations,
    required this.slotKey,
  });
}
