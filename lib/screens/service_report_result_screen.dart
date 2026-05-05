import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../providers/sheets_provider.dart';

class ServiceReportResultScreen extends StatefulWidget {
  const ServiceReportResultScreen({super.key});

  @override
  State<ServiceReportResultScreen> createState() =>
      _ServiceReportResultScreenState();
}

class _ServiceReportResultScreenState
    extends State<ServiceReportResultScreen> {
  static const Color _primaryBlue = Color(0xFF047CBC);

  bool _loading = true;
  String? _error;
  List<_ReportItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime _toDt(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String && v.isNotEmpty) {
      try {
        return DateTime.parse(v.replaceAll('/', '-'));
      } catch (_) {}
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> _load() async {
    final sheets = context.read<SheetsProvider>();
    try {
      final userName = sheets.currentUserName ?? '';
      final rows = await FirestoreService.getPreachingReportsForUser(userName);

      if (mounted) {
        setState(() {
          // 月ごとに最新タイムスタンプの1件だけ残す
          final latestByMonth = <int, _ReportItem>{};
          final latestDtByMonth = <int, DateTime>{};

          for (final row in rows) {
            final monthVal = row['month'];
            int? month;
            if (monthVal is int) month = monthVal;
            else if (monthVal is num) month = monthVal.toInt();
            else if (monthVal is String) month = int.tryParse(monthVal);
            if (month == null) continue;

            final dt = _toDt(row['timestamp']);
            final role = (row['role'] ?? '').toString();
            final participation = (row['participation'] ?? '').toString();
            final hours = row['hours'];
            final hoursStr = hours == null ? '' : hours.toString();
            final participationOrHours =
                participation.isNotEmpty ? participation : hoursStr;

            final bibleStudy = row['bibleStudy'];
            final bibleStudyStr =
                bibleStudy == null ? '' : bibleStudy.toString();

            final item = _ReportItem(
              timestamp: dt,
              month: month,
              role: role,
              participationOrHours: participationOrHours,
              bibleStudy: bibleStudyStr,
              remarks: (row['remarks'] ?? '').toString(),
            );

            final existing = latestDtByMonth[month];
            if (existing == null || dt.isAfter(existing)) {
              latestDtByMonth[month] = dt;
              latestByMonth[month] = item;
            }
          }

          final resultList = latestByMonth.values.toList();
          resultList.sort((a, b) => b.timestamp.compareTo(a.timestamp));

          _items = resultList;
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

  String _formatDate(DateTime dt) {
    if (dt.millisecondsSinceEpoch == 0) return '';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('奉仕報告提出結果'),
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
            const Icon(Icons.inbox, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('提出履歴がありません',
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

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _buildCard(_items[index]),
    );
  }

  Widget _buildCard(_ReportItem item) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _primaryBlue, width: 2.0),
        boxShadow: [
          BoxShadow(
            color: _primaryBlue.withOpacity(0.10),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: _primaryBlue, size: 20),
              const SizedBox(width: 8),
              Text(
                '${item.month}月',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                item.role,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const Spacer(),
              Text(
                _formatDate(item.timestamp),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildRow('参加/時間', item.participationOrHours),
          if (item.bibleStudy.isNotEmpty)
            _buildRow('聖書研究', item.bibleStudy),
          if (item.remarks.isNotEmpty)
            _buildRow('備考', item.remarks),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportItem {
  final DateTime timestamp;
  final int month;
  final String role;
  final String participationOrHours;
  final String bibleStudy;
  final String remarks;

  const _ReportItem({
    required this.timestamp,
    required this.month,
    required this.role,
    required this.participationOrHours,
    required this.bibleStudy,
    required this.remarks,
  });
}
