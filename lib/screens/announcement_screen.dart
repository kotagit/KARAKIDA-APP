import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

class AnnouncementScreen extends StatefulWidget {
  const AnnouncementScreen({super.key});

  @override
  State<AnnouncementScreen> createState() => _AnnouncementScreenState();
}

class _AnnouncementScreenState extends State<AnnouncementScreen>
    with SingleTickerProviderStateMixin {
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
      final snap = await FirebaseFirestore.instance
          .collection('ANNOUNCEMENT')
          .orderBy('date', descending: true)
          .limit(100)
          .get();

      final now = DateTime.now();
      final sevenDaysAgo = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 7));

      final List<Map<String, dynamic>> current = [];
      final List<Map<String, dynamic>> past = [];

      for (final doc in snap.docs) {
        final d = doc.data();
        final ts = d['date'];
        final DateTime date = ts is Timestamp
            ? ts.toDate()
            : DateTime.tryParse(ts.toString()) ?? DateTime(2000);

        final List<Map<String, String>> links = [];
        if (d['links'] is List) {
          for (final l in d['links'] as List) {
            if (l is Map && l['url'] != null && (l['url'] as String).isNotEmpty) {
              links.add({
                'url': l['url'].toString(),
                'label': (l['title'] ?? '資料を開く').toString(),
                'type': 'link',
              });
            }
          }
        }
        // レガシーフィールド（link1_*, link2_*）
        for (final n in ['1', '2']) {
          final url = (d['link${n}_url'] ?? '').toString();
          final title = (d['link${n}_title'] ?? '').toString();
          if (url.isNotEmpty) {
            links.add({'url': url, 'label': title.isEmpty ? '資料を開く' : title, 'type': 'link'});
          }
        }
        // Googleフォーム
        final gfUrl = (d['googleFormUrl'] ?? '').toString();
        if (gfUrl.isNotEmpty) {
          final gfTitle = (d['googleFormTitle'] ?? '').toString();
          links.add({
            'url': gfUrl,
            'label': gfTitle.isEmpty ? 'Googleフォーム' : gfTitle,
            'type': 'form',
          });
        }

        final item = {
          'date': date,
          'title': (d['title'] ?? '').toString(),
          'body': (d['body'] ?? '').toString(),
          'links': links,
        };

        if (date.isAfter(sevenDaysAgo) || date.isAtSameMomentAs(sevenDaysAgo)) {
          current.add(item);
        } else {
          past.add(item);
        }
      }

      if (!mounted) return;
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
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.normal, fontSize: 15),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.7),
          indicatorColor: Theme.of(context).colorScheme.secondary,
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

  static const _wd = ['日', '月', '火', '水', '木', '金', '土'];

  Widget _buildList(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.article_outlined, size: 48, color: Color(0xFF999999)),
              SizedBox(height: 8),
              Text('発表はありません', style: TextStyle(color: Color(0xFF666666))),
            ],
          ),
        ),
      );
    }

    // 日付でグループ化（年月日（曜））
    final groups = <String, List<Map<String, dynamic>>>{};
    final groupOrder = <String>[];
    for (final item in data) {
      final DateTime d = item['date'] as DateTime;
      final key = '${d.year}年${d.month}月${d.day}日（${_wd[d.weekday % 7]}）';
      if (!groups.containsKey(key)) {
        groups[key] = [];
        groupOrder.add(key);
      }
      groups[key]!.add(item);
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: groupOrder.length,
        itemBuilder: (context, index) {
          final dateKey = groupOrder[index];
          final items = groups[dateKey]!;
          return _buildGroup(dateKey, items);
        },
      ),
    );
  }

  Widget _buildGroup(String dateKey, List<Map<String, dynamic>> items) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12),
            child: Text(
              dateKey,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: primary,
              ),
            ),
          ),
          Container(
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  Container(
                    width: double.infinity,
                    color: i.isOdd ? const Color(0xFFF0F7FF) : Colors.white,
                    padding: const EdgeInsets.all(20),
                    child: _buildItem(items[i]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final String title = item['title'] as String;
    final String body = item['body'] as String;
    final links = List<Map<String, String>>.from(item['links']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF222222),
              ),
            ),
          ),
        if (body.isNotEmpty)
          Text(
            body,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF222222),
              height: 1.6,
            ),
          ),
        if (links.isNotEmpty) ...[
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: links.map((link) {
              final isForm = link['type'] == 'form';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  onTap: () => _openUrl(link['url']!),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isForm ? Icons.assignment_outlined : Icons.open_in_new,
                        size: 16,
                        color: isForm
                            ? const Color(0xFF673AB7)
                            : const Color(0xFF222222),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          link['label']!,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isForm
                                ? const Color(0xFF673AB7)
                                : const Color(0xFF222222),
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
