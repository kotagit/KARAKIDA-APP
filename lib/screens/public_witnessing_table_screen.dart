import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

class PublicWitnessingTableScreen extends StatefulWidget {
  const PublicWitnessingTableScreen({super.key});

  @override
  State<PublicWitnessingTableScreen> createState() => _PublicWitnessingTableScreenState();
}

class _PublicWitnessingTableScreenState extends State<PublicWitnessingTableScreen> {
  
  static const double _colWidth = 110.0;
  bool _loading = true;
  String? _error;
  List<_SlotData> _slots = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final options = await FirestoreService.getPublicWitnessingOptions();
      final assignments = await FirestoreService.getAllPublicWitnessingAssignments();
      
      final Map<String, Map<String, dynamic>> assMap = {};
      for (final doc in assignments) {
        assMap[doc['id'] as String] = doc;
      }

      // 日付と時間でグループ化
      // key: "date_time", value: List of assignments
      final Map<String, List<_PlaceAssignment>> groups = {};
      final List<String> sortedKeys = [];

      for (final opt in options) {
        final dateStr = (opt['day'] ?? '').toString();
        final weekday = (opt['dayofweek'] ?? '').toString();
        final startTime = (opt['starttime'] ?? '').toString();
        final placeBase = (opt['place'] ?? '').toString().replaceAll('駅', ''); // "唐木田" or "堀之内"
        
        final groupKey = '${dateStr}_${startTime}_$placeBase';
        if (!sortedKeys.contains(groupKey)) sortedKeys.add(groupKey);

        final fullPlaces = _getFullPlaceNames(weekday, startTime, (opt['place'] ?? '').toString());
        for (final fp in fullPlaces) {
          final docId = '${dateStr}_${startTime}_$fp';
          final doc = assMap[docId];
          final ass = doc?['assignments'] as Map<String, dynamic>? ?? {};
          
          groups.putIfAbsent(groupKey, () => []).add(_PlaceAssignment(
            placeName: fp,
            majorPlace: placeBase,
            conductor: ass['司会者'] as String?,
            participants: List<String?>.from(ass['参加者'] ?? List.filled(5, null)),
          ));
        }
      }

      final loadedSlots = sortedKeys.map<_SlotData>((key) {
        final parts = key.split('_');
        final date = parts[0];
        final time = parts[1];
        final majorPlace = parts[2];

        final opt = options.firstWhere((o) => o['day'].toString() == date);
        final String weekday = (opt['dayofweek'] ?? '').toString();

        return _SlotData(
          date: date,
          weekday: weekday,
          time: time,
          majorPlace: majorPlace,
          allSubAssignments: groups[key]!,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _slots = loadedSlots;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Load Error: $e');
      if (mounted) {
        setState(() {
          _error = '読み込みに失敗しました';
          _loading = false;
        });
      }
    }
  }

  List<String> _getFullPlaceNames(String weekday, String time, String place) {
    if (place.contains('唐木田')) return ['唐木田駅構内'];
    if (place.contains('堀之内')) {
      final base = '堀之内駅';
      if (weekday == '水' && time == '18:00') return ['${base}三和前', '${base}FM前'];
      return ['${base}三和前', '${base}FM前', '${base}信号前'];
    }
    return [place];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('公共エリア伝道 取決表'),
        titleTextStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(() { _loading = true; _load(); })),
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
    if (_slots.isEmpty) return const Center(child: Text('取決め情報がありません'));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _slots.length,
      itemBuilder: (context, index) {
        final slot = _slots[index];
        final bool isNewDay = index == 0 || _slots[index - 1].date != slot.date;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (index > 0) const SizedBox(height: 24),
            _buildSlotHeader(slot, isNewDay),
            const SizedBox(height: 4),
            _buildTimeTable(slot),
          ],
        );
      },
    );
  }

  Widget _buildSlotHeader(_SlotData slot, bool showDate) {
    final bool isWeekend = slot.weekday == '土' || slot.weekday == '日';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDate) ...[
            Text(
              '${slot.date}(${slot.weekday})',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isWeekend ? Colors.red.shade700 : Colors.black87,
              ),
            ),
            SizedBox(width: 12),
          ],
          Icon(Icons.access_time, size: 18, color: Theme.of(context).colorScheme.primary),
          SizedBox(width: 4),
          Text(
            slot.time,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.location_on_outlined, size: 18, color: Colors.grey),
          const SizedBox(width: 4),
          Text(
            slot.majorPlace,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeTable(_SlotData slot) {
    final double fullTableWidth = _colWidth * 3 + 2;
    final container = Container(
      width: _colWidth * slot.allSubAssignments.length + 2,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black, width: 1.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7), // Border thickness 1.0 なので内側をわずかに小さく
        child: Column(
          children: [
            // 場所行 (小項目)
            _buildSubPlaceRow(slot),
            // 司会者行
            _buildMemberRow(slot, (p) => p.conductor, isConductor: true),
            // 参加者行 (5行分)
            ...List.generate(5, (idx) {
              final bool isLastRow = idx == 4;
              return _buildMemberRow(
                slot,
                (p) => p.participants.length > idx ? p.participants[idx] : null,
                isConductor: false,
                showBottomBorder: !isLastRow,
              );
            }),
          ],
        ),
      ),
    );
    if (slot.allSubAssignments.length >= 3) {
      return Align(alignment: Alignment.center, child: container);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final leftOffset = ((constraints.maxWidth - fullTableWidth) / 2).clamp(0.0, double.infinity);
        return Padding(padding: EdgeInsets.only(left: leftOffset), child: container);
      },
    );
  }

  Widget _buildSubPlaceRow(_SlotData slot) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black, width: 1.0)),
      ),
      child: Row(
        children: slot.allSubAssignments.map((sub) {
          final bool isLast = sub == slot.allSubAssignments.last;
          return Container(
            width: _colWidth,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: isLast ? null : const Border(right: BorderSide(color: Colors.black, width: 1.0)),
            ),
            child: Text(
              sub.placeName.replaceAll('堀之内駅', '').replaceAll('唐木田', ''),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMemberRow(_SlotData slot, String? Function(_PlaceAssignment) getName, {required bool isConductor, bool showBottomBorder = true}) {
    return Container(
      decoration: BoxDecoration(
        border: showBottomBorder ? Border(bottom: BorderSide(color: Colors.black, width: isConductor ? 1.0 : 0.5)) : null,
      ),
      child: Row(
        children: slot.allSubAssignments.map((sub) {
          final name = getName(sub);
          final bool isLast = sub == slot.allSubAssignments.last;
          return Container(
            width: _colWidth,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              border: isLast ? null : Border(right: BorderSide(color: Colors.black, width: 1.0)),
            ),
            child: Text(
              name ?? '',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isConductor ? FontWeight.bold : FontWeight.normal,
                color: isConductor ? Theme.of(context).colorScheme.primary : Colors.black87,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLabelCell(String label) {
    return Container(
      width: 60,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: const Border(right: BorderSide(color: Colors.black, width: 1.0)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildPlaceCell(String text, {required Color color, bool showRightBorder = true}) {
    return Container(
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        border: showRightBorder ? const Border(right: BorderSide(color: Colors.black, width: 1.0)) : null,
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _SlotData {
  final String date;
  final String weekday;
  final String time;
  final String majorPlace;
  final List<_PlaceAssignment> allSubAssignments;
  _SlotData({
    required this.date,
    required this.weekday,
    required this.time,
    required this.majorPlace,
    required this.allSubAssignments,
  });
}

class _PlaceAssignment {
  final String placeName;
  final String majorPlace;
  final String? conductor;
  final List<String?> participants;
  _PlaceAssignment({required this.placeName, required this.majorPlace, this.conductor, required this.participants});
}
