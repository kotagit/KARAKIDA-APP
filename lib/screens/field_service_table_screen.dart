import 'package:flutter/material.dart';
import '../services/firestore_service.dart';

class FieldServiceTableScreen extends StatefulWidget {
  const FieldServiceTableScreen({super.key});

  @override
  State<FieldServiceTableScreen> createState() => _FieldServiceTableScreenState();
}

class _FieldServiceTableScreenState extends State<FieldServiceTableScreen> {
  static const _dow = ['日', '月', '火', '水', '木', '金', '土'];

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    _weekStart = _getWeekStart(DateTime.now());
    _load();
  }

  DateTime _getWeekStart(DateTime d) {
    final wd = d.weekday; // 月=1..日=7
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: wd - 1));
  }

  String _fmtShort(DateTime d) => '${d.month}/${d.day}';
  String _dowOf(String dateStr) {
    final d = DateTime.tryParse(dateStr);
    if (d == null) return '';
    return _dow[d.weekday % 7];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await FirestoreService.getFieldServiceForWeek(_weekStart);
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '読み込みに失敗しました';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final weekEnd = _weekStart.add(const Duration(days: 6));
    final weekLabel =
        '${_fmtShort(_weekStart)}(${_dow[_weekStart.weekday % 7]}) 〜 ${_fmtShort(weekEnd)}(${_dow[weekEnd.weekday % 7]})';

    return Scaffold(
      appBar: AppBar(
        title: const Text('野外奉仕取決表'),
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                '※全ての取決めの集合場所はZoom会議室（33 2314 1914）です。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFFD32F2F)),
              ),
            ),
            Center(
              child: Text(
                weekLabel,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(_error!, style: const TextStyle(color: Colors.red))),
              )
            else if (_rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: Text('この週の取決めはありません')),
              )
            else
              _buildTable(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(ColorScheme cs) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final r in _rows) {
      final date = (r['date'] ?? '').toString();
      grouped.putIfAbsent(date, () => []).add(r);
    }
    final dates = grouped.keys.toList()..sort();

    final borderColor = Colors.grey.shade300;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          // ヘッダー
          Container(
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.1),
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: const Row(
              children: [
                _HeaderCell(text: '日付', flex: 0, fixedWidth: 56),
                _HeaderCell(text: '時間', flex: 14),
                _HeaderCell(text: '種別', flex: 10),
                _HeaderCell(text: '司会者', flex: 14),
              ],
            ),
          ),
          for (var i = 0; i < dates.length; i++)
            _buildDayBlock(
              dates[i],
              grouped[dates[i]]!,
              i,
              borderColor,
              isLast: i == dates.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _buildDayBlock(
    String date,
    List<Map<String, dynamic>> rows,
    int dayIdx,
    Color borderColor, {
    required bool isLast,
  }) {
    final dow = _dowOf(date);
    final dateColor = dow == '土'
        ? const Color(0xFF1976D2)
        : dow == '日'
            ? const Color(0xFFD32F2F)
            : Colors.black87;
    final bg = dayIdx % 2 == 0 ? Colors.white : const Color(0xFFFAFAFA);
    final d = DateTime.tryParse(date);
    final dateLabel = d == null ? date : '${d.month}/${d.day}';

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: isLast ? null : Border(bottom: BorderSide(color: borderColor)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 56,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: borderColor)),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(dateLabel,
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold, color: dateColor)),
                      Text(dow, style: TextStyle(fontSize: 12, color: dateColor)),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++)
                    Container(
                      decoration: BoxDecoration(
                        border: i == rows.length - 1
                            ? null
                            : Border(bottom: BorderSide(color: borderColor, width: 0.5)),
                      ),
                      child: Row(
                        children: [
                          _BodyCell(
                            flex: 14,
                            primary: (rows[i]['time'] ?? '').toString(),
                            secondary: (rows[i]['place'] ?? '').toString(),
                          ),
                          _Divider(color: borderColor),
                          _BodyCell(flex: 10, primary: (rows[i]['type'] ?? '').toString()),
                          _Divider(color: borderColor),
                          _BodyCell(
                            flex: 14,
                            primary: (rows[i]['conductor'] ?? '').toString(),
                            secondary: (rows[i]['conductorSub'] ?? '').toString(),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  final int flex;
  final double? fixedWidth;
  const _HeaderCell({required this.text, required this.flex, this.fixedWidth});

  @override
  Widget build(BuildContext context) {
    final cell = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
      ),
    );
    if (fixedWidth != null) return SizedBox(width: fixedWidth, child: cell);
    return Expanded(flex: flex, child: cell);
  }
}

class _BodyCell extends StatelessWidget {
  final int flex;
  final String primary;
  final String secondary;
  const _BodyCell({required this.flex, required this.primary, this.secondary = ''});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(primary, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
            if (secondary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  secondary,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final Color color;
  const _Divider({required this.color});

  @override
  Widget build(BuildContext context) {
    return VerticalDivider(width: 1, thickness: 0.5, color: color);
  }
}
