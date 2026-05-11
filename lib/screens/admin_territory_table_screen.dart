import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

class AdminTerritoryTableScreen extends StatefulWidget {
  const AdminTerritoryTableScreen({super.key});

  @override
  State<AdminTerritoryTableScreen> createState() => _AdminTerritoryTableScreenState();
}

class _AdminTerritoryTableScreenState extends State<AdminTerritoryTableScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await FirestoreService.getTerritoryTableData();
      if (mounted) setState(() { _rows = rows; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '読み込みに失敗しました: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('S-13 区域割当て一覧'),
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        actions: [
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _load,
            ),
        ],
      ),
      body: _buildBody(context, primary),
    );
  }

  Widget _buildBody(BuildContext context, Color primary) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('再読み込み')),
          ],
        ),
      );
    }
    if (_rows.isEmpty) {
      return const Center(child: Text('データがありません'));
    }

    final sorted = List<Map<String, dynamic>>.from(_rows)
      ..sort((a, b) {
        final na = int.tryParse(a['territory']?.toString() ?? '');
        final nb = int.tryParse(b['territory']?.toString() ?? '');
        if (na != null && nb != null) return na.compareTo(nb);
        return (a['territory']?.toString() ?? '').compareTo(b['territory']?.toString() ?? '');
      });

    const labelStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 12);
    const cellStyle = TextStyle(fontSize: 12);
    const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 8);

    Widget cell(String text, {bool bold = false}) => Padding(
      padding: padding,
      child: Text(text, style: bold ? labelStyle : cellStyle, textAlign: TextAlign.center),
    );

    TableRow buildRow(String label, String Function(Map<String, dynamic>) value, {Color? bg}) {
      return TableRow(
        decoration: bg != null ? BoxDecoration(color: bg) : null,
        children: [
          cell(label, bold: true),
          ...sorted.map((r) => cell(value(r))),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Table(
            border: TableBorder.all(color: Colors.grey.shade300, width: 1),
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              // ヘッダー行: 区域番号
              TableRow(
                decoration: BoxDecoration(color: primary.withOpacity(0.15)),
                children: [
                  cell('', bold: true),
                  ...sorted.map((r) => cell(r['territory']?.toString() ?? '', bold: true)),
                ],
              ),
              buildRow('名前', (r) => r['supervisorName']?.toString() ?? ''),
              buildRow('開始', (r) => r['startDate']?.toString() ?? '',
                  bg: primary.withOpacity(0.05)),
              buildRow('終了', (r) => r['endDate']?.toString() ?? ''),
            ],
          ),
        ),
      ),
    );
  }
}
