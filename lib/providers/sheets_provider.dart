import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../services/sheets_service.dart';
import '../services/api_service.dart';
import '../services/firestore_service.dart';

class SheetsProvider extends ChangeNotifier {
  SheetsService? _sheetsService;
  StreamSubscription? _addressesSub;
  StreamSubscription? _paramsSub;
  Timer? _paramsCheckTimer;
  Map<String, dynamic>? _latestParamsSnapshot;

  // State — カード表示用
  String? _selectedCardName;
  List<Map<String, dynamic>> _cardAddresses = [];
  bool _isLoading = false;
  String? _error;
  bool _isNightCard = false;
  bool get isNightCard => _isNightCard;
  bool _isAutolockCard = false;
  bool get isAutolockCard => _isAutolockCard;

  // オートロックカードを開いた時の直近編集者警告
  List<Map<String, dynamic>> _recentAutolockEditors = [];
  List<Map<String, dynamic>> get recentAutolockEditors => _recentAutolockEditors;
  bool _isCheckingEditors = false;
  bool get isCheckingEditors => _isCheckingEditors;
  void clearRecentAutolockEditors() {
    _recentAutolockEditors = [];
    notifyListeners();
  }

  // Access control
  String? _currentUserName;
  String? _currentUserGroupName;
  String? _currentUserFurigana;
  bool _isAdmin = false;
  bool _isCho = false;
  bool _isTerritoryServant = false;
  bool _isPW = false;
  String? _currentUserRole;
  String? _currentUserGender;
  String? _currentUserEmail;
  String? get currentUserName => _currentUserName;
  String? get currentUserGroupName => _currentUserGroupName;
  String? get currentUserFurigana => _currentUserFurigana;
  String? get currentUserEmail => _currentUserEmail;
  String? get currentUserRole => _currentUserRole;
  String? get currentUserGender => _currentUserGender;
  bool get isAdmin => _isAdmin;
  bool get isCho => _isCho;
  bool get isTerritoryServant => _isTerritoryServant;
  bool get isPW => _isPW;

  // Visit period from Firestore config
  String? _visitStartDate;
  String? _visitEndDate;
  String? get visitStartDate => _visitStartDate;
  String? get visitEndDate => _visitEndDate;

  String? _nightStartDate;
  String? _nightEndDate;
  String? get nightStartDate => _nightStartDate;
  String? get nightEndDate => _nightEndDate;

  // Getters
  String? get selectedCardName => _selectedCardName;
  List<Map<String, dynamic>> get cardAddresses => _cardAddresses;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ── SS用（奉仕報告・公共エリア・発表・組織で引き続き使用） ──
  // 組織画面で使用
  List<List<dynamic>> _data = [];
  List<List<dynamic>> get data => _data;
  Map<String, String> _linksByKey = {};
  Map<String, int> _colorsByKey = {};
  Map<String, String> get linksByKey => _linksByKey;
  Map<String, int> get colorsByKey => _colorsByKey;

  // SS用のスプレッドシート情報（組織画面で使用）
  String? _selectedSpreadsheetId;
  String? _selectedSpreadsheetName;
  String? get selectedSpreadsheetId => _selectedSpreadsheetId;
  String? get selectedSpreadsheetName => _selectedSpreadsheetName;

  // Para spreadsheet ID（SS残留機能で使用）
  static const String _paramId = '1xyPtpHlJ9P1BquQ48TfC9rg99wXFMXE0bfg6MiUvQ_E';

  /// 認証ヘッダーのみ更新（トークンリフレッシュ用）
  void updateAuthHeaders(Map<String, String> headers) {
    _sheetsService = SheetsService(headers);
  }

  /// GASから取得したユーザー情報で認証状態を更新する
  void updateAuth(Map<String, String>? headers, {String? name, String? group, String? furigana, bool isAdmin = false, bool isCho = false, bool isTerritoryServant = false, bool isPW = false, String? email}) {
    if (headers == null) {
      _sheetsService = null;
      stopListening();
      _stopWatchingParams();
      _reset();
      notifyListeners();
      return;
    }
    _reset();
    _sheetsService = SheetsService(headers);
    _currentUserName = name;
    _currentUserGroupName = group;
    _currentUserFurigana = furigana;
    _isAdmin = isAdmin;
    _isCho = isCho;
    _isTerritoryServant = isTerritoryServant;
    _isPW = isPW;
    _currentUserEmail = email;
    debugPrint('Auth Updated: Name="$_currentUserName", Group="$_currentUserGroupName", Admin=$_isAdmin, Cho=$_isCho, TS=$_isTerritoryServant, PW=$_isPW');
    _startWatchingParams();
    notifyListeners();
  }

  /// 日付文字列 "yyyy/M/d" を DateTime に変換
  DateTime? _parseConfigDate(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final parts = s.split('/');
      if (parts.length != 3) return null;
      return DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    } catch (_) {
      return null;
    }
  }

  /// startDateが今日以降なら「まだ開始していない」＝適用せず現状維持
  /// ただし現状値が未設定の場合は最初の読み込みとみなして適用する
  bool _shouldApplyNewDate(String? newStart, String? currentStart) {
    final nowDate = DateTime.now();
    final today = DateTime(nowDate.year, nowDate.month, nowDate.day);
    final newDt = _parseConfigDate(newStart);
    if (newDt == null) return false;
    // 初回読み込み（まだ何も設定されていない）なら常に適用
    if (currentStart == null || currentStart.isEmpty) return true;
    // 今日が新startDate以降なら適用、まだ前なら無視
    return !today.isBefore(newDt);
  }

  /// CONFIGの最新スナップショットを評価して、適用可能なら適用する
  void _evaluateParams() {
    final params = _latestParamsSnapshot;
    if (params == null) return;

    final newVisitStart = params['visitStartDate'] as String?;
    final newVisitEnd = params['visitEndDate'] as String?;
    final newNightStart = params['nightStartDate'] as String?;
    final newNightEnd = params['nightEndDate'] as String?;

    bool changed = false;

    if (_shouldApplyNewDate(newVisitStart, _visitStartDate)) {
      if (newVisitStart != _visitStartDate || newVisitEnd != _visitEndDate) {
        _visitStartDate = newVisitStart;
        _visitEndDate = newVisitEnd;
        changed = true;
      }
    } else {
      debugPrint('CONFIG: 昼間の新しい開始日($newVisitStart)はまだ未来なので現行値($_visitStartDate)を維持');
    }

    if (_shouldApplyNewDate(newNightStart, _nightStartDate)) {
      if (newNightStart != _nightStartDate || newNightEnd != _nightEndDate) {
        _nightStartDate = newNightStart;
        _nightEndDate = newNightEnd;
        changed = true;
      }
    } else {
      debugPrint('CONFIG: 夜間の新しい開始日($newNightStart)はまだ未来なので現行値($_nightStartDate)を維持');
    }

    if (changed) {
      debugPrint('CONFIG applied: visit=$_visitStartDate~$_visitEndDate, night=$_nightStartDate~$_nightEndDate');
      notifyListeners();
    }
  }

  /// CONFIGのリアルタイム監視を開始
  void _startWatchingParams() {
    _paramsSub?.cancel();
    _paramsCheckTimer?.cancel();

    _paramsSub = FirestoreService.watchParams().listen((params) {
      if (params == null) return;
      _latestParamsSnapshot = params;
      _evaluateParams();
    });

    // 1時間ごとに「開始日が来た」かを再評価する
    _paramsCheckTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _evaluateParams();
    });
  }

  void _stopWatchingParams() {
    _paramsSub?.cancel();
    _paramsSub = null;
    _paramsCheckTimer?.cancel();
    _paramsCheckTimer = null;
    _latestParamsSnapshot = null;
  }

  void _reset() {
    _selectedCardName = null;
    _cardAddresses = [];
    _isNightCard = false;
    _isAutolockCard = false;
    _selectedSpreadsheetId = null;
    _selectedSpreadsheetName = null;
    _data = [];
    _linksByKey = {};
    _colorsByKey = {};
    _currentUserName = null;
    _currentUserGroupName = null;
    _currentUserFurigana = null;
    _currentUserEmail = null;
    _isAdmin = false;
    _isCho = false;
    _isTerritoryServant = false;
    _isPW = false;
    _visitStartDate = null;
    _visitEndDate = null;
    _nightStartDate = null;
    _nightEndDate = null;
    _error = null;
  }

  String _normName(String name) {
    return name.replaceAll(RegExp(r'[\s\u3000]+'), '').trim();
  }

  // ──────────────────────────────────────────────
  // 初期化（Firestoreからパラメータ読み込み）
  // ──────────────────────────────────────────────

  Future<void> loadFiles({String? userEmail}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      // Firestoreからパラメータを読み込み
      final params = await FirestoreService.getParams();
      if (params != null) {
        _visitStartDate = params['visitStartDate'] as String?;
        _visitEndDate = params['visitEndDate'] as String?;
        _nightStartDate = params['nightStartDate'] as String?;
        _nightEndDate = params['nightEndDate'] as String?;
      }
      debugPrint('Visit dates from Firestore: Start=$_visitStartDate, End=$_visitEndDate');
      debugPrint('Night dates from Firestore: Start=$_nightStartDate, End=$_nightEndDate');
    } catch (e) {
      _error = '初期化に失敗しました: $e';
      debugPrint('loadFiles error: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadAccessControl(String email) async {
    try {
      // 異なるアカウントの場合はユーザー情報をリセット
      if (_currentUserEmail != null && _currentUserEmail != email) {
        _currentUserName = null;
        _currentUserGroupName = null;
        _currentUserFurigana = null;
        _currentUserEmail = null;
        _isAdmin = false;
        _isCho = false;
        _isTerritoryServant = false;
        _isPW = false;
        _currentUserRole = null;
        _currentUserGender = null;
      }
      // Firestoreからユーザー情報を取得
      if (_currentUserName == null || _currentUserName!.isEmpty) {
        final userData = await FirestoreService.getUserByEmail(email);
        if (userData != null) {
          _currentUserEmail = email; // 成功時のみ保持（失敗時は再試行できるよう保持しない）
          _currentUserName = userData['name'] as String?;
          _currentUserGroupName = userData['group'] as String?;
          _currentUserFurigana = userData['furigana'] as String?;
          _isAdmin = userData['isAdmin'] == true;
          _isCho = userData['isCho'] == true;
          _isTerritoryServant = userData['isTerritoryServant'] == true;
          _isPW = userData['isPW'] == true;
          _currentUserRole = userData['role'] as String?;
          _currentUserGender = userData['gender'] as String?;
          notifyListeners(); // 取得成功時にUIへ通知
        }
      }

      // パラメータ読み込み
      if (_visitStartDate == null) {
        final params = await FirestoreService.getParams();
        if (params != null) {
          _visitStartDate = params['visitStartDate'] as String?;
          _visitEndDate = params['visitEndDate'] as String?;
          _nightStartDate = params['nightStartDate'] as String?;
          _nightEndDate = params['nightEndDate'] as String?;
        }
      }

      debugPrint('loadAccessControl: Name=$_currentUserName, Group=$_currentUserGroupName, Admin=$_isAdmin');
    } catch (e) {
      debugPrint('loadAccessControl error: $e');
    }
  }

  // ──────────────────────────────────────────────
  // グループ・区域（Firestore）
  // ──────────────────────────────────────────────

  Future<List<String>> loadGroupNames() async {
    try {
      return await FirestoreService.getGroupNames();
    } catch (e) {
      debugPrint('loadGroupNames error: $e');
      return [];
    }
  }

  Future<List<String>> loadTerritoriesForGroup(String groupName) async {
    try {
      return await FirestoreService.getTerritoriesForGroup(groupName);
    } catch (e) {
      debugPrint('loadTerritoriesForGroup error: $e');
      return [];
    }
  }

  Future<List<String>> loadNightTerritoriesForGroup(String groupName) async {
    try {
      return await FirestoreService.getNightTerritories();
    } catch (e) {
      debugPrint('loadNightTerritoriesForGroup error: $e');
      return [];
    }
  }

  // ──────────────────────────────────────────────
  // 割当て（Firestore）
  // ──────────────────────────────────────────────

  /// ユーザーに割当てられたカード名リストを取得
  Future<List<Map<String, dynamic>>> getAssignedCardsForUser() async {
    if (_currentUserName == null) return [];
    try {
      final cardNames = await FirestoreService.getAssignedCardNamesForUser(_currentUserName!);
      if (cardNames.isEmpty) return [];

      final cards = await FirestoreService.getCardsByNames(cardNames);
      // 数値順ソート
      cards.sort((a, b) {
        final aName = a['id'] as String? ?? '';
        final bName = b['id'] as String? ?? '';
        final aMatch = RegExp(r'(\d+)-(\d+)').firstMatch(aName);
        final bMatch = RegExp(r'(\d+)-(\d+)').firstMatch(bName);
        if (aMatch != null && bMatch != null) {
          final aFirst = int.parse(aMatch.group(1)!);
          final aSecond = int.parse(aMatch.group(2)!);
          final bFirst = int.parse(bMatch.group(1)!);
          final bSecond = int.parse(bMatch.group(2)!);
          if (aFirst != bFirst) return aFirst.compareTo(bFirst);
          return aSecond.compareTo(bSecond);
        }
        return aName.compareTo(bName);
      });
      return cards;
    } catch (e) {
      debugPrint('getAssignedCardsForUser error: $e');
      return [];
    }
  }

  /// カードを選択してデータを読み込む（通常区域）
  Future<void> selectCard(String cardName) async {
    _selectedCardName = cardName;
    _isNightCard = false;
    _cardAddresses = [];
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _cardAddresses = await FirestoreService.getNormalCardDataWithHistory(cardName);
    } catch (e, st) {
      _error = 'カードデータの取得に失敗しました: $e';
      debugPrint('selectCard ERROR: $e\n$st');
    }
    _isLoading = false;
    notifyListeners();
  }

  /// ステータスを更新（通常カード → AREA_DATA_NORMAL_HISTORY に書き込み）
  Future<void> updateVisitStatus(String addressId, String statusResult) async {
    debugPrint('updateVisitStatus: card=$_selectedCardName, addressId=$addressId, status=$statusResult, startDate=$_visitStartDate, endDate=$_visitEndDate');
    if (_selectedCardName == null) {
      _error = '保存できません: カードが選択されていません';
      notifyListeners();
      return;
    }

    // 訪問期間が未設定の場合は今日の日付をデフォルト使用
    final now = DateTime.now();
    final todayStr = '${now.year}/${now.month}/${now.day}';
    final effectiveStart = _visitStartDate ?? todayStr;
    final effectiveEnd = _visitEndDate ?? todayStr;

    try {
      await FirestoreService.updateNormalVisitStatus(
        cardName: _selectedCardName!,
        addressId: addressId,
        startDate: effectiveStart,
        endDate: effectiveEnd,
        staffName: _currentUserName ?? '',
        statusResult: statusResult,
      );

      // ローカルデータも更新
      final idx = _cardAddresses.indexWhere((a) => a['id'] == addressId);
      if (idx >= 0) {
        final visitId = '${effectiveStart}_$effectiveEnd';
        final visits = List<Map<String, dynamic>>.from(_cardAddresses[idx]['visits'] ?? []);
        final existingIdx = visits.indexWhere((v) => v['id'] == visitId);
        final visitData = {
          'id': visitId,
          'staffName': _currentUserName ?? '',
          'startDate': effectiveStart,
          'endDate': effectiveEnd,
          'statusResult': statusResult,
        };
        if (existingIdx >= 0) {
          visits[existingIdx] = visitData;
        } else {
          visits.insert(0, visitData);
        }
        _cardAddresses[idx] = {..._cardAddresses[idx], 'visits': visits, 'currentVisit': visitData};
      }
      notifyListeners();
    } catch (e) {
      _error = 'ステータスの更新に失敗しました: $e';
      notifyListeners();
    }
  }

  /// オートロックカードを選択してデータを読み込む
  Future<void> selectAutolockCard(String cardName) async {
    _selectedCardName = cardName;
    _isNightCard = false;
    _isAutolockCard = true;
    _cardAddresses = [];
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _cardAddresses = await FirestoreService.getAutolockCardDataWithHistory(cardName);
    } catch (e) {
      _error = 'カードデータの取得に失敗しました: $e';
    }
    _isLoading = false;
    notifyListeners();

    // 編集者チェック（失敗してもカード表示に影響しない）
    _isCheckingEditors = true;
    try {
      _recentAutolockEditors = await FirestoreService.getRecentAutolockEditors(
        cardName,
        excludeStaff: _currentUserName,
      );
    } catch (e) {
      debugPrint('getRecentAutolockEditors error (non-fatal): $e');
      _recentAutolockEditors = [];
    }
    _isCheckingEditors = false;
    notifyListeners();
  }

  /// 夜間カードを選択してデータを読み込む
  Future<void> selectNightCard(String cardName) async {
    _selectedCardName = cardName;
    _isNightCard = true;
    _cardAddresses = [];
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // GROUP_ASS_NO から夜間訪問期間を取得（startDate が今日以前のものに限定）
      final assignment = await FirestoreService.getLatestGroupAssignment(
        '会衆',
        type: 'NIGHT',
        currentOnly: true,
      );
      if (assignment.startDate != null && assignment.startDate!.isNotEmpty) {
        _nightStartDate = assignment.startDate;
        _nightEndDate = assignment.endDate;
        debugPrint('selectNightCard: night period = $_nightStartDate ~ $_nightEndDate');
      }

      _cardAddresses = await FirestoreService.getNightCardDataWithHistory(cardName);
    } catch (e) {
      _error = 'カードデータの取得に失敗しました: $e';
    }
    _isLoading = false;
    notifyListeners();
  }

  /// オートロックカードのステータスを更新（AREA_DATA_AUTOLOCK_HISTORY に書き込み）
  Future<void> updateAutolockVisitStatus(String uid, String statusResult) async {
    debugPrint('updateAutolockVisitStatus: card=$_selectedCardName, uid=$uid, status=$statusResult, start=$_visitStartDate, end=$_visitEndDate');
    if (_selectedCardName == null) {
      _error = '保存できません: カードが選択されていません';
      notifyListeners();
      return;
    }

    final now = DateTime.now();
    final todayStr = '${now.year}/${now.month}/${now.day}';
    final effectiveStart = _visitStartDate ?? todayStr;
    final effectiveEnd = _visitEndDate ?? todayStr;

    try {
      await FirestoreService.updateAutolockVisitStatus(
        cardName: _selectedCardName!,
        addressId: uid,
        startDate: effectiveStart,
        endDate: effectiveEnd,
        staffName: _currentUserName ?? '',
        statusResult: statusResult,
      );

      // ローカルデータも更新（uid フィールドで該当行を検索）
      final idx = _cardAddresses.indexWhere((a) => a['uid'] == uid);
      if (idx >= 0) {
        final visitId = '${effectiveStart}_$effectiveEnd';
        final visits = List<Map<String, dynamic>>.from(_cardAddresses[idx]['visits'] ?? []);
        final existingIdx = visits.indexWhere((v) => v['id'] == visitId);
        final visitData = {
          'id': visitId,
          'staffName': _currentUserName ?? '',
          'startDate': effectiveStart,
          'endDate': effectiveEnd,
          'statusResult': statusResult,
        };
        if (existingIdx >= 0) {
          visits[existingIdx] = visitData;
        } else {
          visits.insert(0, visitData);
        }
        _cardAddresses[idx] = {
          ..._cardAddresses[idx],
          'visits': visits,
          'currentVisit': visitData,
        };
      }
      notifyListeners();
    } catch (e) {
      _error = 'ステータスの更新に失敗しました: $e';
      notifyListeners();
    }
  }

  /// 夜間カードのステータスを更新（AREA_DATA_NIGHT_HISTORY に書き込み）
  Future<void> updateNightVisitStatus(String addressId, String statusResult) async {
    debugPrint('updateNightVisitStatus: card=$_selectedCardName, addr=$addressId, status=$statusResult, start=$_nightStartDate, end=$_nightEndDate');
    if (_selectedCardName == null) {
      _error = '保存できません: カードが選択されていません';
      notifyListeners();
      return;
    }

    // night 期間が未設定の場合は今日の日付をデフォルト使用
    final now = DateTime.now();
    final todayStr = '${now.year}/${now.month}/${now.day}';
    final effectiveStart = _nightStartDate ?? todayStr;
    final effectiveEnd = _nightEndDate ?? todayStr;

    try {
      await FirestoreService.updateNightVisitStatus(
        cardName: _selectedCardName!,
        addressId: addressId,
        startDate: effectiveStart,
        endDate: effectiveEnd,
        staffName: _currentUserName ?? '',
        statusResult: statusResult,
      );

      // ローカルデータも更新
      final idx = _cardAddresses.indexWhere((a) => a['id'] == addressId);
      if (idx >= 0) {
        final visitId = '${effectiveStart}_$effectiveEnd';
        final visits = List<Map<String, dynamic>>.from(_cardAddresses[idx]['visits'] ?? []);
        final existingIdx = visits.indexWhere((v) => v['id'] == visitId);
        final visitData = {
          'id': visitId,
          'staffName': _currentUserName ?? '',
          'startDate': effectiveStart,
          'endDate': effectiveEnd,
          'statusResult': statusResult,
        };
        if (existingIdx >= 0) {
          visits[existingIdx] = visitData;
        } else {
          visits.insert(0, visitData);
        }
        _cardAddresses[idx] = {
          ..._cardAddresses[idx],
          'visits': visits,
          'currentVisit': visitData,
        };
      }
      notifyListeners();
    } catch (e) {
      _error = 'ステータスの更新に失敗しました: $e';
      notifyListeners();
    }
  }

  /// リアルタイムリスナーを開始（通常／夜間を自動判別）
  void startListening() {
    if (_selectedCardName == null) return;
    stopListening();
    if (_isAutolockCard) {
      // AREA_DATA_AUTOLOCK にはリアルタイムリスナー不使用（手動リフレッシュのみ）
      return;
    }
    if (_isNightCard) {
      _addressesSub = FirestoreService.watchNightAddresses(_selectedCardName!).listen((addresses) async {
        _cardAddresses = await FirestoreService.getNightCardDataWithHistory(_selectedCardName!);
        notifyListeners();
      });
    } else {
      _addressesSub = FirestoreService.watchNormalAddresses(_selectedCardName!).listen((addresses) async {
        _cardAddresses = await FirestoreService.getNormalCardDataWithHistory(_selectedCardName!);
        notifyListeners();
      });
    }
  }

  void stopListening() {
    _addressesSub?.cancel();
    _addressesSub = null;
  }

  // 旧ポーリングAPIとの互換性
  void startPolling() => startListening();
  void stopPolling() => stopListening();

  // ──────────────────────────────────────────────
  // 区域カードファイル一覧（Firestore）
  // ──────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getTerritoryCardFiles(
    String groupName,
    String territoryNumber, {
    bool isNight = false,
  }) async {
    try {
      final cards = await FirestoreService.getCardsForTerritory(territoryNumber);
      // 管理画面では、その区域番号に属する全てのカードを表示対象とする
      // (フィルタリングをスキップして確実に表示させる)
      return cards;
    } catch (e) {
      debugPrint('getTerritoryCardFiles error: $e');
      return [];
    }
  }

  // ──────────────────────────────────────────────
  // 割当て管理（Firestore）
  // ──────────────────────────────────────────────

  Future<Map<String, String>> getAssignmentsForTerritory(
    String groupName,
    String territoryNumber, {
    bool isNight = false,
  }) async {
    try {
      final assignments = await FirestoreService.getAssignmentsForTerritory(
        groupName, territoryNumber, isNight: isNight,
      );
      final result = <String, String>{};

      for (final a in assignments) {
        final cardName = FirestoreService.cardNameFromDoc(a);
        final memberName = a['memberName']?.toString() ?? '';

        if (cardName.isEmpty || memberName.isEmpty) continue;

        // FirestoreService 側でタイムスタンプ比較済みのため、そのまま採用
        if (!result.containsKey(cardName)) {
          result[cardName] = memberName;
        }
      }
      return result;
    } catch (e) {
      debugPrint('getAssignmentsForTerritory error: $e');
      return {};
    }
  }

  Future<List<Map<String, String>>> getAllAssignmentsForGroup(String groupName, {bool isNight = false}) async {
    try {
      final rawEntries = isNight
          ? await loadNightTerritoriesForGroup(groupName)
          : await loadTerritoriesForGroup(groupName);

      final prefixes = rawEntries
          .map((e) => isNight ? e.toString().trim() : e.split('-')[0].trim())
          .where((p) => p.isNotEmpty)
          .toSet()
          .toList();

      final assignments = <Map<String, String>>[];

      // 全ての区域カードと割り当て情報を並列で取得して高速化
      final results = await Future.wait(prefixes.map((prefix) async {
        final cardsFuture = getTerritoryCardFiles(groupName, prefix, isNight: isNight);
        final assignedFuture = getAssignmentsForTerritory(
          isNight ? '夜間区域' : groupName,
          prefix,
          isNight: isNight,
        );
        return await Future.wait([cardsFuture, assignedFuture]);
      }));

      for (int i = 0; i < prefixes.length; i++) {
        final prefix = prefixes[i];
        final cards = results[i][0] as List<Map<String, dynamic>>;
        final assigned = results[i][1] as Map<String, String>;

        for (final card in cards) {
          final cardName = _normCardName(card['id'] as String? ?? '');
          assignments.add({
            'territory': prefix,
            'cardName': cardName,
            'memberName': assigned[cardName] ?? '未割当て',
          });
        }
      }
      return assignments;
    } catch (e) {
      debugPrint('getAllAssignmentsForGroup error: $e');
      return [];
    }
  }

  Future<void> saveGroupMembersToData3(
    String groupName,
    String territoryNumber,
    List<List<dynamic>> data, {
    bool isNight = false,
  }) async {
    try {
      final type = isNight ? 'NIGHT' : 'NORMAL';
      final assignment = await FirestoreService.getLatestGroupAssignment(groupName, type: type);
      final startDate = assignment.startDate ?? _visitStartDate;
      final endDate = assignment.endDate ?? _visitEndDate;
      debugPrint('saveGroupMembersToData3: period from GROUP_ASS_NO = ${assignment.startDate} ~ ${assignment.endDate}, fallback CONFIG = $_visitStartDate ~ $_visitEndDate, effective = $startDate ~ $endDate');

      await FirestoreService.saveAssignmentsBatch(
        groupName,
        territoryNumber,
        data,
        isNight: isNight,
        startDate: startDate,
        endDate: endDate,
      );
      debugPrint('Saved assignments to Firestore for $groupName/$territoryNumber');
    } catch (e) {
      debugPrint('saveGroupMembersToData3 error: $e');
      rethrow;
    }
  }

  /// グループのメンバー一覧を取得（Firestoreのusersコレクションから）
  Future<List<String>> loadGroupMembers(String groupName) async {
    try {
      return await FirestoreService.getMembersByGroup(groupName);
    } catch (e) {
      debugPrint('loadGroupMembers error: $e');
      return [];
    }
  }

  // ──────────────────────────────────────────────
  // SS残留機能（奉仕報告・公共エリア・発表・組織）
  // ──────────────────────────────────────────────

  /// 申込み結果シートから現在のユーザーの提出分を取得
  Future<List<List<dynamic>>> readApplicationResultsForUser(
    String spreadsheetId,
    String sheetName,
  ) async {
    if (_currentUserName == null) return [];
    final all = await ApiService.readRange(sheetName, spreadsheetId: spreadsheetId);
    return all
        .where((row) =>
            row.length >= 2 &&
            row[1].toString().trim() == _currentUserName!.trim())
        .toList();
  }

  Future<List<List<dynamic>>> readParamData4() async {
    return await ApiService.readRange('data4', spreadsheetId: _paramId);
  }

  Future<List<List<int?>>> readParamData4Colors() async {
    if (_sheetsService == null) return [];
    return await _sheetsService!.readCellColors(_paramId, 'data4');
  }

  Future<List<String>> getSheetNamesFor(String spreadsheetId) async {
    final ids = await ApiService.getSheetIds(spreadsheetId);
    return ids.keys.toList();
  }

  Future<String?> getSheetNameByGid(String spreadsheetId, int gid) async {
    final ids = await ApiService.getSheetIds(spreadsheetId);
    for (final entry in ids.entries) {
      if (entry.value == gid) return entry.key;
    }
    return null;
  }

  Future<void> appendRowTo(String spreadsheetId, String sheet, List<dynamic> row) async {
    if (_sheetsService == null) return;
    await _sheetsService!.appendRange(spreadsheetId, '$sheet!A:Z', [row]);
  }

  Future<void> appendRowToFirst(String spreadsheetId, List<dynamic> row) async {
    if (_sheetsService == null) return;
    await _sheetsService!.appendRange(spreadsheetId, 'A:Z', [row]);
  }

  Future<List<List<dynamic>>> readFromFirstForUser(String spreadsheetId) async {
    if (_currentUserName == null) return [];
    final all = await ApiService.readRange('data', spreadsheetId: spreadsheetId);
    final currentNorm = _normName(_currentUserName!);
    return all
        .where((row) =>
            row.length >= 2 &&
            _normName(row[1].toString()) == currentNorm)
        .toList();
  }

  Future<List<List<dynamic>>> readRangeFor(String spreadsheetId, String sheet) async {
    return await ApiService.readRange(sheet, spreadsheetId: spreadsheetId);
  }

  Future<List<List<int?>>> readCellColorsFor(String spreadsheetId, String sheet) async {
    if (_sheetsService == null) return [];
    return await _sheetsService!.readCellColors(spreadsheetId, sheet);
  }

  Future<List<Map<String, int>>> readMergesFor(String spreadsheetId, String sheet) async {
    if (_sheetsService == null) return [];
    return await _sheetsService!.readMerges(spreadsheetId, sheet);
  }

  // ──────────────────────────────────────────────
  // ユーティリティ
  // ──────────────────────────────────────────────

  String _normCardName(String name) {
    return name.trim().replaceAll(RegExp(r'[−–ー\uff70\u2010—―]'), '-');
  }

  @override
  void dispose() {
    _stopWatchingParams();
    stopListening();
    super.dispose();
  }
}
