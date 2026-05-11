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

  Widget _buildList(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return const Center(child: Text('データがありません'));
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: data.length,
        itemBuilder: (context, index) {
          final item = data[index];
          final DateTime date = item['date'] as DateTime;
          final String dateStr =
              '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
          final String title = item['title'] as String;
          final String body = item['body'] as String;
          final List<Map<String, String>> links =
              List<Map<String, String>>.from(item['links']);

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 4,
            shadowColor: Colors.black12,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                      color: Theme.of(context).colorScheme.primary, width: 6),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_today_rounded,
                              size: 14,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.tertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (title.isNotEmpty)
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
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: links.map((link) {
                          final isForm = link['type'] == 'form';
                          return ElevatedButton.icon(
                            icon: Icon(
                              isForm ? Icons.assignment_outlined : Icons.description_rounded,
                              size: 18,
                            ),
                            label: Text(
                              link['label']!,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isForm
                                  ? const Color(0xFF673AB7)
                                  : Theme.of(context).colorScheme.secondary,
                              foregroundColor:
                                  isForm ? Colors.white : const Color(0xFF1E293B),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => _openUrl(link['url']!),
                          );
                        }).toList(),
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

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
