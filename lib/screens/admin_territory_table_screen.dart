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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(primary.withOpacity(0.1)),
          border: TableBorder.all(color: Colors.grey.shade300, width: 1),
          columnSpacing: 24,
          columns: const [
            DataColumn(label: Text('区域番号', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('監督名', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('開始日付', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(label: Text('終了日付', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: _rows.map((row) {
            return DataRow(cells: [
              DataCell(Text(row['territory'] as String? ?? '')),
              DataCell(Text(row['supervisorName'] as String? ?? '')),
              DataCell(Text(row['startDate'] as String? ?? '')),
              DataCell(Text(row['endDate'] as String? ?? '')),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}
