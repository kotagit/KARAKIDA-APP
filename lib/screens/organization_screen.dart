import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../providers/sheets_provider.dart';

class OrganizationScreen extends StatefulWidget {
  const OrganizationScreen({super.key});

  static const String spreadsheetId =
      '1vgjr5Q_7LHqqplYAwub0-MINxYGxe3GCqsPOd8853vY';

  @override
  State<OrganizationScreen> createState() => _OrganizationScreenState();
}

class _OrganizationScreenState extends State<OrganizationScreen> {
  
  static const double _baseCellHeight = 30.0;
  static const double _baseColWidth = 60.0;
  double _scale = 1.0;

  List<String> _sheetNames = [];
  String? _selectedSheet;
  List<List<dynamic>> _data = [];
  List<List<int?>> _colors = [];
  List<Map<String, int>> _merges = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSheetNames();
  }

  Future<void> _loadSheetNames() async {
    final sheets = context.read<SheetsProvider>();
    try {
      final names = await sheets.getSheetNamesFor(OrganizationScreen.spreadsheetId);
      if (mounted) {
        setState(() {
          _sheetNames = names;
          _loading = false;
        });
        if (names.isNotEmpty) {
          _selectSheet(names.first);
        }
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

  Future<void> _selectSheet(String sheetName) async {
    setState(() {
      _selectedSheet = sheetName;
      _loading = true;
      _error = null;
    });
    final sheets = context.read<SheetsProvider>();
    try {
      final results = await Future.wait([
        sheets.readRangeFor(OrganizationScreen.spreadsheetId, sheetName),
        sheets.readCellColorsFor(OrganizationScreen.spreadsheetId, sheetName),
        sheets.readMergesFor(OrganizationScreen.spreadsheetId, sheetName),
      ]);
      if (mounted) {
        setState(() {
          _data = results[0] as List<List<dynamic>>;
          _colors = results[1] as List<List<int?>>;
          _merges = results[2] as List<Map<String, int>>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'データの取得に失敗しました: $e';
          _loading = false;
        });
      }
    }
  }

  int? _getCellColor(int row, int col) {
    if (row < _colors.length && col < _colors[row].length) {
      return _colors[row][col];
    }
    return null;
  }

  /// Check if this cell is hidden by a merge (i.e. it's not the top-left cell of a merge)
  bool _isHiddenByMerge(int row, int col) {
    for (final m in _merges) {
      final sr = m['startRow']!;
      final er = m['endRow']!;
      final sc = m['startCol']!;
      final ec = m['endCol']!;
      if (row >= sr && row < er && col >= sc && col < ec) {
        if (row != sr || col != sc) return true;
      }
    }
    return false;
  }

  /// Get the merge span for a cell (returns null if not a merge start)
  Map<String, int>? _getMergeSpan(int row, int col) {
    for (final m in _merges) {
      if (m['startRow'] == row && m['startCol'] == col) {
        return {
          'rowSpan': m['endRow']! - m['startRow']!,
          'colSpan': m['endCol']! - m['startCol']!,
        };
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('組織'),
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.zoom_in),
            onPressed: () => setState(() => _scale = (_scale + 0.1).clamp(0.5, 2.0)),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out),
            onPressed: () => setState(() => _scale = (_scale - 0.1).clamp(0.5, 2.0)),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_sheetNames.length > 1)
            Container(
              color: Colors.grey.shade100,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: _sheetNames.map((name) {
                    final isSelected = name == _selectedSheet;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(name, style: TextStyle(fontSize: 12)),
                        selected: isSelected,
                        selectedColor: Theme.of(context).colorScheme.primary,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                        onSelected: (_) => _selectSheet(name),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (_data.isEmpty) {
      return const Center(child: Text('データがありません'));
    }

    int maxCols = 0;
    for (final row in _data) {
      if (row.length > maxCols) maxCols = row.length;
    }
    final totalRows = _data.length;
    final cellHeight = _baseCellHeight * _scale;

    // Calculate column widths based on content
    final colWidths = List.filled(maxCols, _baseColWidth * _scale);
    for (int c = 0; c < maxCols; c++) {
      double maxWidth = 40.0;
      for (int r = 0; r < totalRows; r++) {
        if (r < _data.length && c < _data[r].length) {
          final text = _data[r][c].toString();
          final w = text.length * 9.0 + 12.0;
          if (w > maxWidth) maxWidth = w;
        }
      }
      colWidths[c] = (maxWidth.clamp(30.0, 120.0)) * _scale;
    }

    final totalWidth = colWidths.fold(0.0, (sum, w) => sum + w);
    final totalHeight = totalRows * cellHeight;

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalWidth,
          height: totalHeight,
          child: Stack(
            children: _buildCells(totalRows, maxCols, colWidths, cellHeight),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCells(int totalRows, int maxCols, List<double> colWidths, double cellHeight) {
    final widgets = <Widget>[];
    final fontSize = (11.0 * _scale).clamp(8.0, 20.0);

    for (int r = 0; r < totalRows; r++) {
      for (int c = 0; c < maxCols; c++) {
        if (_isHiddenByMerge(r, c)) continue;

        final span = _getMergeSpan(r, c);
        final rowSpan = span?['rowSpan'] ?? 1;
        final colSpan = span?['colSpan'] ?? 1;

        final left = _colOffset(c, colWidths);
        final top = r * cellHeight;
        final width = _spanWidth(c, colSpan, colWidths);
        final height = rowSpan * cellHeight;

        String val = (r < _data.length && c < _data[r].length)
            ? _data[r][c].toString()
            : '';
        // 「組織表」の記載は非表示
        if (val == '組織表') val = '';

        final bgColor = _getCellColor(r, c);
        final hasBg = bgColor != null;

        // 日付判定（YYYY/MM/DD や YYYY-MM-DD 形式）
        final isDate = RegExp(r'^\d{4}[/\-]\d{1,2}[/\-]\d{1,2}$').hasMatch(val);

        widgets.add(
          Positioned(
            left: left,
            top: top,
            width: width,
            height: height,
            child: Container(
              decoration: BoxDecoration(
                color: hasBg ? Color(bgColor) : null,
                border: hasBg
                    ? Border.all(color: Colors.grey.shade400, width: 0.5)
                    : null,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              alignment: isDate ? Alignment.centerRight : Alignment.centerLeft,
              child: Text(
                val,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: hasBg ? FontWeight.w500 : FontWeight.normal,
                ),
                softWrap: true,
                maxLines: null,
              ),
            ),
          ),
        );
      }
    }

    return widgets;
  }

  double _colOffset(int col, List<double> colWidths) {
    double offset = 0;
    for (int i = 0; i < col; i++) {
      offset += colWidths[i];
    }
    return offset;
  }

  double _spanWidth(int startCol, int colSpan, List<double> colWidths) {
    double w = 0;
    for (int i = startCol; i < startCol + colSpan && i < colWidths.length; i++) {
      w += colWidths[i];
    }
    return w;
  }
}
