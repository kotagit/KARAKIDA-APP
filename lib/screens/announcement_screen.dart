import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

class AnnouncementScreen extends StatefulWidget {
  const AnnouncementScreen({super.key});

  @override
  State<AnnouncementScreen> createState() => _AnnouncementScreenState();
}

class _AnnouncementScreenState extends State<AnnouncementScreen>
    with SingleTickerProviderStateMixin {
  static const String _spreadsheetId =
      '14FhgXBNYQhJxnV9xTp4J5wEuh2jUkgjpAVvVD2jXAyc';

  late TabController _tabController;
  List<Map<String, dynamic>> _currentData = [];
  List<Map<String, dynamic>> _oldData = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        ApiService.readRange('data', spreadsheetId: _spreadsheetId),
        ApiService.readRange('data_OLD', spreadsheetId: _spreadsheetId),
      ]);

      if (!mounted) return;
      
      // data と data_OLD の全データを取得し、ヘッダーを除外して結合
      final allRawRows = [
        ...results[0].length > 1 ? results[0].sublist(1) : [],
        ...results[1].length > 1 ? results[1].sublist(1) : [],
      ];

      // --- 1. まず全データをグループ化する（空欄行を親行に合体させる） ---
      final List<Map<String, dynamic>> allAnnouncements = [];
      String lastDateStr = '';
      String lastTitle = '';
      String lastBody = '';

      for (final row in allRawRows) {
        final dateStr = row.isNotEmpty ? row[0].toString().trim() : '';
        final title = row.length > 1 ? row[1].toString().trim() : '';
        final body = row.length > 2 ? row[2].toString().trim() : '';

        // リンク (docname, url) を抽出
        final List<Map<String, String>> rowLinks = [];
        for (int i = 3; i < row.length; i += 2) {
          final String docName = row[i].toString().trim();
          final String url = (i + 1 < row.length) ? row[i + 1].toString().trim() : '';
          if (url.isNotEmpty) {
            rowLinks.add({'url': url, 'label': docName.isNotEmpty ? docName : '資料を開く'});
          }
        }

        final bool isContinuation = dateStr.isEmpty && title.isEmpty && body.isEmpty;

        if (isContinuation && allAnnouncements.isNotEmpty) {
          // 継続行であれば、直前の発表内容にリンクを追加
          (allAnnouncements.last['links'] as List<Map<String, String>>).addAll(rowLinks);
        } else {
          // 新しい発表内容として追加
          if (dateStr.isNotEmpty) lastDateStr = dateStr;
          if (title.isNotEmpty) lastTitle = title;
          if (body.isNotEmpty) lastBody = body;
          
          allAnnouncements.add({
            'date': lastDateStr,
            'title': lastTitle,
            'body': lastBody,
            'links': List<Map<String, String>>.from(rowLinks),
          });
        }
      }

      // --- 2. 日付を判定して「今週」と「過去」に振り分け、それぞれソートする ---
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final sevenDaysAgo = today.subtract(const Duration(days: 7));

      final List<Map<String, dynamic>> current = [];
      final List<Map<String, dynamic>> past = [];

      for (final item in allAnnouncements) {
        final dateStr = item['date'] as String;
        DateTime? rowDate;
        
        final parts = dateStr.split('/');
        if (parts.length == 3) {
          rowDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        } else {
          rowDate = DateTime.tryParse(dateStr);
        }

        final bool isRecent = rowDate != null && 
            (rowDate.isAfter(sevenDaysAgo) || rowDate.isAtSameMomentAs(sevenDaysAgo));

        if (isRecent) {
          current.add(item);
        } else {
          past.add(item);
        }
      }

      // 日付の新しい順（降順）にソート
      int compareItems(Map<String, dynamic> a, Map<String, dynamic> b) {
        final dateStrA = a['date'] as String;
        final dateStrB = b['date'] as String;
        DateTime? dateA;
        final pA = dateStrA.split('/');
        dateA = pA.length == 3 ? DateTime(int.parse(pA[0]), int.parse(pA[1]), int.parse(pA[2])) : DateTime.tryParse(dateStrA);
        DateTime? dateB;
        final pB = dateStrB.split('/');
        dateB = pB.length == 3 ? DateTime(int.parse(pB[0]), int.parse(pB[1]), int.parse(pB[2])) : DateTime.tryParse(dateStrB);

        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateB.compareTo(dateA);
      }

      current.sort(compareItems);
      past.sort(compareItems);

      setState(() {
        _currentData = current;
        _oldData = past;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('発表'),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 15),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.7),
          indicatorColor: const Color(0xFFF1C232),
          indicatorWeight: 4,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: '今週'),
            Tab(text: '過去'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('エラー: $_error'))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildList(_currentData),
                    _buildList(_oldData),
                  ],
                ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> groupedData) {
    if (groupedData.isEmpty) {
      return const Center(child: Text('データがありません'));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: groupedData.length,
        itemBuilder: (context, index) {
          final item = groupedData[index];
          final String date = _formatDate(item['date'].toString());
          final String title = item['title'].toString();
          final String body = item['body'].toString();
          final List<Map<String, String>> links = List<Map<String, String>>.from(item['links']);

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 4,
            shadowColor: Colors.black12,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Color(0xFF047CBC), width: 6),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 日付バッジ風表示
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF047CBC).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFF047CBC)),
                          const SizedBox(width: 6),
                          Text(
                            date,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF047CBC),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 主題
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E293B),
                        height: 1.2,
                      ),
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        body,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF475569),
                          height: 1.5,
                        ),
                      ),
                    ],
                    if (links.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      // リンクをポップなボタンとして表示
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: links.map((link) => ElevatedButton.icon(
                              icon: const Icon(Icons.description_rounded, size: 18),
                              label: Text(
                                link['label']!,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF1C232),
                                foregroundColor: const Color(0xFF1E293B),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () => _openUrl(link['url']!),
                            )).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(String raw) {
    // "2026-03-30T15:00:00.000Z" → "2026/03/30"
    final dt = DateTime.tryParse(raw);
    if (dt != null) {
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
    }
    // ISO形式でなければTより前を返す
    final tIndex = raw.indexOf('T');
    if (tIndex > 0) return raw.substring(0, tIndex);
    return raw;
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
