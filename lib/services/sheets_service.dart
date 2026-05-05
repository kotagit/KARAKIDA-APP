import 'dart:convert';
import 'package:http/http.dart' as http;

class SheetsService {
  static const String _baseUrl =
      'https://sheets.googleapis.com/v4/spreadsheets';

  final Map<String, String> _authHeaders;

  SheetsService(this._authHeaders);

  /// Fetch all sheet names (tabs) in a spreadsheet
  Future<List<String>> getSheetNames(String spreadsheetId) async {
    final url = '$_baseUrl/$spreadsheetId?fields=sheets.properties.title';
    final response = await http.get(Uri.parse(url), headers: _authHeaders);
    if (response.statusCode != 200) {
      throw Exception('Failed to load sheet names: ${response.body}');
    }
    final data = json.decode(response.body);
    final sheets = data['sheets'] as List;
    return sheets
        .map((s) => s['properties']['title'] as String)
        .toList();
  }

  /// Read a range of cells from a sheet
  Future<List<List<dynamic>>> readRange(
    String spreadsheetId,
    String range,
  ) async {
    final encodedRange = Uri.encodeComponent(range);
    final url = '$_baseUrl/$spreadsheetId/values/$encodedRange';
    final response = await http.get(Uri.parse(url), headers: _authHeaders);
    if (response.statusCode != 200) {
      throw Exception('Failed to read range: ${response.body}');
    }
    final data = json.decode(response.body);
    final values = data['values'] as List?;
    if (values == null) return [];
    return values.map((row) => (row as List).toList()).toList();
  }

  /// Write values to a range
  Future<void> writeRange(
    String spreadsheetId,
    String range,
    List<List<dynamic>> values,
  ) async {
    final encodedRange = Uri.encodeComponent(range);
    final url =
        '$_baseUrl/$spreadsheetId/values/$encodedRange?valueInputOption=USER_ENTERED';
    final body = json.encode({'values': values});
    final response = await http.put(
      Uri.parse(url),
      headers: {
        ..._authHeaders,
        'Content-Type': 'application/json',
      },
      body: body,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to write range: ${response.body}');
    }
  }

  /// Clear a range (delete all values)
  Future<void> clearRange(
    String spreadsheetId,
    String range,
  ) async {
    final encodedRange = Uri.encodeComponent(range);
    final url =
        '$_baseUrl/$spreadsheetId/values/$encodedRange:clear';
    final response = await http.post(
      Uri.parse(url),
      headers: {
        ..._authHeaders,
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to clear range: ${response.body}');
    }
  }

  /// Append rows after existing data
  Future<void> appendRange(
    String spreadsheetId,
    String range,
    List<List<dynamic>> values,
  ) async {
    final encodedRange = Uri.encodeComponent(range);
    final url =
        '$_baseUrl/$spreadsheetId/values/$encodedRange:append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS';
    final body = json.encode({'values': values});
    final response = await http.post(
      Uri.parse(url),
      headers: {
        ..._authHeaders,
        'Content-Type': 'application/json',
      },
      body: body,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to append range: ${response.body}');
    }
  }

  /// Fetch merge information for a specific sheet
  /// Returns list of {startRow, endRow, startCol, endCol}
  Future<List<Map<String, int>>> readMerges(
    String spreadsheetId,
    String sheetName,
  ) async {
    // First get the sheetId for the given sheetName
    final url = '$_baseUrl/$spreadsheetId?fields=sheets(properties,merges)';
    final response = await http.get(Uri.parse(url), headers: _authHeaders);
    if (response.statusCode != 200) return [];
    final data = json.decode(response.body);
    final sheets = data['sheets'] as List?;
    if (sheets == null) return [];

    for (final sheet in sheets) {
      final title = sheet['properties']?['title'] as String?;
      if (title == sheetName) {
        final merges = sheet['merges'] as List?;
        if (merges == null) return [];
        return merges.map<Map<String, int>>((m) {
          return {
            'startRow': (m['startRowIndex'] ?? 0) as int,
            'endRow': (m['endRowIndex'] ?? 0) as int,
            'startCol': (m['startColumnIndex'] ?? 0) as int,
            'endCol': (m['endColumnIndex'] ?? 0) as int,
          };
        }).toList();
      }
    }
    return [];
  }

  /// Fetch background colors for a range (returns ARGB int, null = default/white)
  Future<List<List<int?>>> readCellColors(
    String spreadsheetId,
    String range,
  ) async {
    final encodedRange = Uri.encodeComponent(range);
    final url =
        '$_baseUrl/$spreadsheetId?ranges=$encodedRange&fields=sheets.data.rowData.values.userEnteredFormat.backgroundColor&includeGridData=true';
    final response = await http.get(Uri.parse(url), headers: _authHeaders);
    if (response.statusCode != 200) return [];
    final data = json.decode(response.body);
    final sheets = data['sheets'] as List?;
    if (sheets == null || sheets.isEmpty) return [];
    final sheetData = sheets[0]['data'] as List?;
    if (sheetData == null || sheetData.isEmpty) return [];
    final rowDataList = sheetData[0]['rowData'] as List?;
    if (rowDataList == null) return [];

    return rowDataList.map<List<int?>>((rowData) {
      final values = (rowData['values'] as List?) ?? [];
      return values.map<int?>((cell) {
        final format = cell['userEnteredFormat'];
        if (format == null) return null;
        final bg = format['backgroundColor'];
        if (bg == null) return null;
        final r = ((bg['red'] ?? 0.0) * 255).round();
        final g = ((bg['green'] ?? 0.0) * 255).round();
        final b = ((bg['blue'] ?? 0.0) * 255).round();
        // Treat near-white as no color
        if (r > 240 && g > 240 && b > 240) return null;
        return (0xFF000000 | (r << 16) | (g << 8) | b);
      }).toList();
    }).toList();
  }

  /// A列の値をキーにしたリンク＋背景色Mapを1回のAPIコールで取得
  Future<({Map<String, String> links, Map<String, int> colors})> readRowMetadata(
    String spreadsheetId,
    String range,
  ) async {
    final empty = (links: <String, String>{}, colors: <String, int>{});
    // シート名をシングルクォートで囲み、全行・全列を明示指定
    final sheetName = range.contains('!') ? range.split('!')[0] : range;
    final fullRange = "'$sheetName'!A1:Z1000";
    final encodedRange = Uri.encodeComponent(fullRange);
    final url =
        '$_baseUrl/$spreadsheetId?ranges=$encodedRange'
        '&fields=sheets.data.rowData.values(formattedValue,hyperlink,textFormatRuns,userEnteredFormat.backgroundColor)'
        '&includeGridData=true';
    final response = await http.get(Uri.parse(url), headers: _authHeaders);
    if (response.statusCode != 200) return empty;
    final data = json.decode(response.body);
    final sheets = data['sheets'] as List?;
    if (sheets == null || sheets.isEmpty) return empty;
    final sheetData = sheets[0]['data'] as List?;
    if (sheetData == null || sheetData.isEmpty) return empty;
    final rowDataList = sheetData[0]['rowData'] as List?;
    if (rowDataList == null) return empty;

    final links = <String, String>{};
    final colors = <String, int>{};

    for (final rowData in rowDataList) {
      final cells = (rowData['values'] as List?) ?? [];
      if (cells.isEmpty) continue;
      // A列＋B列の複合キー（重複防止）
      final aCell = cells[0] is Map ? cells[0] as Map : null;
      final bCell = cells.length > 1 && cells[1] is Map ? cells[1] as Map : null;
      final aKey = (aCell?['formattedValue'] as String?)?.trim() ?? '';
      final bKey = (bCell?['formattedValue'] as String?)?.trim() ?? '';
      final key = aKey.isNotEmpty ? '$aKey|$bKey' : bKey;
      if (key.isEmpty) continue;

      // 全列スキャン: リンクは全列、背景色はA・B列のみ
      for (int ci = 0; ci < cells.length; ci++) {
        final cell = cells[ci];
        if (cell is! Map) continue;
        // リンク（全列）
        if (!links.containsKey(key)) {
          String? link = cell['hyperlink'] as String?;
          if (link == null || link.isEmpty) {
            final runs = cell['textFormatRuns'] as List?;
            if (runs != null) {
              for (final run in runs) {
                final uri = run['format']?['link']?['uri'] as String?;
                if (uri != null && uri.isNotEmpty) { link = uri; break; }
              }
            }
          }
          if (link != null && link.isNotEmpty) links[key] = link;
        }
        // 背景色はA列(0)またはB列(1)のみ対象
        if (ci <= 1 && !colors.containsKey(key)) {
          final bg = cell['userEnteredFormat']?['backgroundColor'];
          if (bg != null) {
            final r = ((bg['red'] ?? 0.0) * 255).round();
            final g = ((bg['green'] ?? 0.0) * 255).round();
            final b = ((bg['blue'] ?? 0.0) * 255).round();
            if (!(r > 220 && g > 220 && b > 220)) {
              colors[key] = (0xFF000000 | (r << 16) | (g << 8) | b);
            }
          }
        }
      }
    }
    print('[Metadata] sheet=$range links=${links.length} colors=${colors.length}');
    colors.forEach((k, v) => print('[Color] key="$k" hex=#${v.toRadixString(16).substring(2)}'));
    return (links: links, colors: colors);
  }

  /// 値とハイパーリンクを1回のAPIコールで同時取得
  /// formattedValue を含めることで全行が返される（リンクのない行も含む）
  Future<({List<List<dynamic>> values, List<List<String?>> links})>
      readRangeWithLinks(String spreadsheetId, String range) async {
    final empty = (
      values: <List<dynamic>>[],
      links: <List<String?>>[],
    );
    final encodedRange = Uri.encodeComponent(range);
    final url =
        '$_baseUrl/$spreadsheetId?ranges=$encodedRange'
        '&fields=sheets.data.rowData.values(formattedValue,hyperlink,textFormatRuns)'
        '&includeGridData=true';
    final response = await http.get(Uri.parse(url), headers: _authHeaders);
    if (response.statusCode != 200) return empty;
    final data = json.decode(response.body);
    final sheets = data['sheets'] as List?;
    if (sheets == null || sheets.isEmpty) return empty;
    final sheetData = sheets[0]['data'] as List?;
    if (sheetData == null || sheetData.isEmpty) return empty;
    final rowDataList = sheetData[0]['rowData'] as List?;
    if (rowDataList == null) return empty;

    final values = <List<dynamic>>[];
    final links = <List<String?>>[];

    for (final rowData in rowDataList) {
      final cells = (rowData['values'] as List?) ?? [];
      final rowValues = <dynamic>[];
      final rowLinks = <String?>[];
      for (final cell in cells) {
        if (cell is! Map) {
          rowValues.add('');
          rowLinks.add(null);
          continue;
        }
        rowValues.add(cell['formattedValue'] ?? '');
        // 1) cell-level hyperlink
        String? link = cell['hyperlink'] as String?;
        // 2) inline textFormatRuns
        if (link == null || link.isEmpty) {
          final runs = cell['textFormatRuns'] as List?;
          if (runs != null) {
            for (final run in runs) {
              final uri = run['format']?['link']?['uri'] as String?;
              if (uri != null && uri.isNotEmpty) {
                link = uri;
                break;
              }
            }
          }
        }
        rowLinks.add((link != null && link.isNotEmpty) ? link : null);
      }
      values.add(rowValues);
      links.add(rowLinks);
    }
    return (values: values, links: links);
  }

  /// Update a single cell
  Future<void> updateCell(
    String spreadsheetId,
    String cell,
    dynamic value,
  ) async {
    await writeRange(spreadsheetId, cell, [
      [value]
    ]);
  }

  /// シート名 → 数値sheetId のマップを取得
  Future<Map<String, int>> getSheetIds(String spreadsheetId) async {
    final url = '$_baseUrl/$spreadsheetId?fields=sheets.properties(title,sheetId)';
    final response = await http.get(Uri.parse(url), headers: _authHeaders);
    if (response.statusCode != 200) {
      throw Exception('Failed to get sheet IDs: ${response.body}');
    }
    final data = json.decode(response.body);
    final sheets = data['sheets'] as List;
    return {
      for (final s in sheets)
        s['properties']['title'] as String: s['properties']['sheetId'] as int,
    };
  }

  /// 指定シートの columnIndex の位置に1列挿入する（0始まり: 2 = C列の前）
  Future<void> insertColumn(
    String spreadsheetId,
    int sheetId,
    int columnIndex,
  ) async {
    final url = '$_baseUrl/$spreadsheetId:batchUpdate';
    final body = json.encode({
      'requests': [
        {
          'insertDimension': {
            'range': {
              'sheetId': sheetId,
              'dimension': 'COLUMNS',
              'startIndex': columnIndex,
              'endIndex': columnIndex + 1,
            },
            'inheritFromBefore': false,
          }
        }
      ],
    });
    final response = await http.post(
      Uri.parse(url),
      headers: {
        ..._authHeaders,
        'Content-Type': 'application/json',
      },
      body: body,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to insert column: ${response.body}');
    }
  }
}
