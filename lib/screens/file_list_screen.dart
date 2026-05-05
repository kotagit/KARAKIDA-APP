import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../providers/sheets_provider.dart';
import 'sheet_view_screen.dart';

class FileListScreen extends StatefulWidget {
  const FileListScreen({super.key});

  @override
  State<FileListScreen> createState() => _FileListScreenState();
}

class _FileListScreenState extends State<FileListScreen> {
  static const Color _primaryBlue = Color(0xFF047CBC);

  bool _loading = true;
  String? _error;
  bool _hasLoaded = false;
  List<Map<String, dynamic>> _personalCards = [];
  List<String> _groupCards = [];
  String _groupName = '';

  String _formatCardName(String name) {
    final normalized = name.replaceAll(RegExp(r'[−–ー]'), '-');
    return '区域No.$normalized';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final sheets = Provider.of<SheetsProvider>(context);
    if (!_hasLoaded && sheets.currentUserName != null) {
      _hasLoaded = true;
      Future.microtask(() => _load());
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    final sheets = Provider.of<SheetsProvider>(context, listen: false);

    setState(() {
      _loading = true;
      _error = null;
    });

    List<Map<String, dynamic>> personalCards = [];
    List<String> groupCards = [];
    List<String> groupTerritories = [];
    final groupName = sheets.currentUserGroupName ?? '';

    // 個人カードとグループ区域カードを並列取得
    await Future.wait([
      sheets.getAssignedCardsForUser().then((v) => personalCards = v).catchError((_) {}),
      if (groupName.isNotEmpty) ...[
        FirestoreService.getGroupAreaCardNames(groupName)
            .then((v) => groupCards = v)
            .catchError((_) {}),
        FirestoreService.getTerritoriesForGroup(groupName)
            .then((v) => groupTerritories = v)
            .catchError((_) {}),
      ],
    ]);

    // GROUP_ASS_NO に基づき、自グループに割当たっていない区域のカードを除外する
    if (groupName.isNotEmpty && groupTerritories.isNotEmpty) {
      personalCards = personalCards.where((card) {
        final cardName = card['id'] as String? ?? '';
        final territory = cardName.split('-').first;
        return groupTerritories.contains(territory);
      }).toList();
      groupCards = groupCards.where((cardName) {
        final territory = cardName.split('-').first;
        return groupTerritories.contains(territory);
      }).toList();
    }

    if (mounted) {
      setState(() {
        _personalCards = personalCards;
        _groupCards = groupCards;
        _groupName = groupName;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheets = context.watch<SheetsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('割当て区域カード'),
        titleTextStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        actions: [
          if (sheets.currentUserName != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  sheets.currentUserName!,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(context, sheets),
    );
  }

  Widget _buildBody(BuildContext context, SheetsProvider sheets) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'あなたに割り当てられた区域カードを読み込んでいます。',
                style: TextStyle(fontSize: 13, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    final userName = sheets.currentUserName ?? '';

    return RefreshIndicator(
      onRefresh: () async {
        _hasLoaded = false;
        await _load();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 担当者タグ ──
            if (userName.isNotEmpty) ...[
              _buildSectionTag(userName),
              const SizedBox(height: 8),
            ],

            // ── 個人カード一覧 ──
            if (_personalCards.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  '割当てられたカードがありません',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              )
            else
              ..._personalCards.map((card) {
                final cardName = card['id'] as String? ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () {
                      sheets.selectCard(cardName);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SheetViewScreen(),
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      child: Row(
                        children: [
                          Image.asset('assets/APP_LOGO_02.png',
                              width: 28, height: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _formatCardName(cardName),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: _primaryBlue,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              color: Colors.grey.shade400),
                        ],
                      ),
                    ),
                  ),
                );
              }),

            // ── グループカードタグ + カード一覧 ──
            if (_groupName.isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildSectionTag('グループカード'),
              const SizedBox(height: 8),
              if (_groupCards.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    '割り当てられた区域はありません',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                )
              else
                ..._groupCards.map((cardName) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () {
                      sheets.selectCard(cardName);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SheetViewScreen(),
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      child: Row(
                        children: [
                          const Icon(Icons.map_outlined, color: _primaryBlue),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _formatCardName(cardName),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: _primaryBlue,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              color: Colors.grey.shade400),
                        ],
                      ),
                    ),
                  ),
                )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTag(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: _primaryBlue,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
