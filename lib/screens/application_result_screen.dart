import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../providers/sheets_provider.dart';
import '../services/firestore_service.dart';

class ApplicationResultScreen extends StatefulWidget {
  const ApplicationResultScreen({super.key});

  @override
  State<ApplicationResultScreen> createState() =>
      _ApplicationResultScreenState();
}

class _ApplicationResultScreenState extends State<ApplicationResultScreen> {
  

  bool _loading = true;
  String? _error;
  List<_ResultItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sheets = context.read<SheetsProvider>();
    final userName = sheets.currentUserName ?? '';
    try {
      // 1. 現在の募集項目を取得（有効な項目のキー集合）
      final options = await FirestoreService.getPublicWitnessingOptions();
      final validKeys = <String>{};
      for (final o in options) {
        final d = (o['day'] ?? '').toString();
        final w = (o['dayofweek'] ?? '').toString();
        final s = (o['starttime'] ?? '').toString();
        final p = (o['place'] ?? '').toString();
        validKeys.add('${d}_${w}_${s}_$p');
      }

      // 2. ユーザーの申込み履歴を取得
      final rows = await FirestoreService.getPublicWitnessingForUser(userName);

      // タイムスタンプ降順 (Timestamp と String の両方に対応)
      DateTime _toDt(dynamic v) {
        if (v is Timestamp) return v.toDate();
        if (v is String && v.isNotEmpty) {
          try {
            return DateTime.parse(v.replaceAll('/', '-'));
          } catch (_) {}
        }
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
      rows.sort((a, b) => _toDt(b['timestamp']).compareTo(_toDt(a['timestamp'])));

      if (mounted) {
        setState(() {
          final seen = <String>{};
          final deduplicated = <_ResultItem>[];

          for (final row in rows) {
            final tsRaw = row['timestamp'];
            final timestamp = tsRaw is Timestamp
                ? tsRaw.toDate().toString()
                : (tsRaw ?? '').toString();
            final date      = (row['day'] ?? '').toString();
            final weekday   = (row['dayofweek'] ?? '').toString();
            final startTime = (row['starttime'] ?? '').toString();
            final place     = (row['place'] ?? '').toString();
            final role      = (row['role'] ?? '').toString();

            final key = '${date}_${weekday}_${startTime}_$place';

            // 現在の募集項目に存在する、かつ重複を除く
            if (validKeys.contains(key) && seen.add(key)) {
              deduplicated.add(_ResultItem(
                timestamp: timestamp,
                date: date,
                weekday: weekday,
                startTime: startTime,
                place: place,
                role: role,
              ));
            }
          }
          _items = deduplicated;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('ApplicationResultScreen load error: $e');
      if (mounted) {
        setState(() {
          _error = '読み込みに失敗しました: $e';
          _loading = false;
        });
      }
    }
  }

  Color _colorForPlace(String place) {
    if (place.contains('唐木田')) return const Color(0xFF90EE90);
    if (place.contains('堀之内')) return const Color(0xFF87CEEB);
    return Colors.grey.shade200;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('公共エリア申込結果'),
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

  Widget _buildNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Text(
        '申込結果は割当てを確定するものではありません。',
        style: TextStyle(
          color: Colors.red,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildBody() {
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('申込み履歴がありません',
                style: TextStyle(color: Colors.grey)),
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
        _buildNotice(),
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
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
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
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildItemCard(_ResultItem item) {
    final placeColor = _colorForPlace(item.place);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2.0),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                item.date,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
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
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                item.startTime,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                  decoration: BoxDecoration(
                    color: placeColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.place,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
                if (item.role.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      item.role,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultItem {
  final String timestamp;
  final String date;
  final String weekday;
  final String startTime;
  final String place;
  final String role;

  const _ResultItem({
    required this.timestamp,
    required this.date,
    required this.weekday,
    required this.startTime,
    required this.place,
    this.role = '',
  });
}
