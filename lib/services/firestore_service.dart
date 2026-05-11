import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FirestoreService {
  static final _db = FirebaseFirestore.instance;

  // ──────────────────────────────────────────────
  // USER_LIST コレクション（許可リスト）
  // ──────────────────────────────────────────────

  /// メールアドレスでユーザー情報を取得（許可チェック兼用）
  static Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final lowerEmail = email.toLowerCase();
    debugPrint('Firestore: getUserByEmail started for "$lowerEmail"');

    try {
      // ネットワークが遅いため、タイムアウトを30秒に延長
      // タイムアウトしてもオフラインキャッシュがあればそれを使用する
      var data = await _lookupUser(collection: 'USER_LIST', email: lowerEmail, emailField: 'mail')
          .timeout(const Duration(seconds: 30));
      
      if (data != null) {
        debugPrint('Firestore: User found in USER_LIST! data=$data');
        _normalizeUserData(data);
        _setAdminFlag(data);
        return data;
      }

      debugPrint('Firestore: User not found in USER_LIST.');
      return null;
    } catch (e) {
      debugPrint('Firestore: getUserByEmail ERROR: $e');
      // タイムアウト等のエラー時でも、キャッシュがあるかもしれないので再試行
      try {
        final snap = await _db.collection('USER_LIST')
            .where('mail', isEqualTo: lowerEmail)
            .get(const GetOptions(source: Source.cache));
        if (snap.docs.isNotEmpty) {
          final data = snap.docs.first.data();
          debugPrint('Firestore: User found in Cache! data=$data');
          _normalizeUserData(data);
          _setAdminFlag(data);
          return data;
        }
      } catch (_) {}
      rethrow;
    }
  }

  /// 指定されたコレクションからユーザーを検索するヘルパー
  static Future<Map<String, dynamic>?> _lookupUser({
    required String collection,
    required String email,
    required String emailField,
  }) async {
    final col = _db.collection(collection);

    // 一時的な通信エラー (unavailable) の場合、最大2回リトライする
    int retryCount = 0;
    const maxRetries = 2;

    while (retryCount <= maxRetries) {
      try {
        // 1. クエリで検索 (emailField が一致するもの)
        final snap = await col
            .where(emailField, isEqualTo: email)
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 10));

        if (snap.docs.isNotEmpty) {
          return snap.docs.first.data();
        }

        // 2. ドキュメントIDで直接取得
        final doc = await col
            .doc(email)
            .get()
            .timeout(const Duration(seconds: 10));
            
        if (doc.exists) {
          return doc.data();
        }

        return null;
      } catch (e) {
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('unavailable') && retryCount < maxRetries) {
          retryCount++;
          debugPrint('Firestore: Service unavailable, retrying ($retryCount/$maxRetries)...');
          await Future.delayed(Duration(seconds: 2 * retryCount)); // 指数バックオフ
          continue;
        }
        rethrow;
      }
    }
    return null;
  }

  /// フィールド名の揺れを吸収（import.js との互換性のため）
  static void _normalizeUserData(Map<String, dynamic> data) {
    // status1 / attribute1
    if (data['status1'] == null && data['attribute1'] != null) {
      data['status1'] = data['attribute1'];
    }
    // status2 / attribute2
    if (data['status2'] == null && data['attribute2'] != null) {
      data['status2'] = data['attribute2'];
    }
    // mail / email
    if (data['mail'] == null && data['email'] != null) {
      data['mail'] = data['email'];
    }
  }

  static void _setAdminFlag(Map<String, dynamic> data) {
    final s1 = (data['status1'] as String? ?? '').toUpperCase();
    final s2 = (data['status2'] as String? ?? '').toUpperCase();
    final s3 = (data['status3'] as String? ?? '').toUpperCase();
    // 司会者: status1 が EL/MS/BR
    data['isCho'] = s1 == 'EL' || s1 == 'MS' || s1 == 'BR';
    // 区域係: status2 が AM
    data['isTerritoryServant'] = s2 == 'AM';
    // 取決め策定者: status3 が PW
    data['isPW'] = s3 == 'PW';
    // 管理画面アクセス可: いずれか該当
    data['isAdmin'] =
        (data['isCho'] as bool) || (data['isTerritoryServant'] as bool) || (data['isPW'] as bool);
  }

  /// グループに所属するメンバー名一覧を取得
  static Future<List<String>> getMembersByGroup(String groupName) async {
    final snap = await _db
        .collection('USER_LIST')
        .where('group', isEqualTo: groupName)
        .get();
    final members = <String>[];
    for (final doc in snap.docs) {
      final name = doc.data()['name'] as String? ?? '';
      if (name.isNotEmpty && name != '氏名' && name != '名前') {
        members.add(name);
      }
    }
    members.sort();
    return members;
  }

  // ──────────────────────────────────────────────
  // config コレクション（パラメータ）
  // ──────────────────────────────────────────────

  /// CONFIGコレクションの最初のドキュメントをリアルタイム監視
  static Stream<Map<String, dynamic>?> watchParams() {
    return _db.collection('CONFIG').limit(1).snapshots().map((snap) {
      if (snap.docs.isEmpty) return null;
      return snap.docs.first.data();
    });
  }

  static Future<Map<String, dynamic>?> getParams() async {
    try {
      final snap = await _db
          .collection('CONFIG')
          .limit(1)
          .get(const GetOptions(source: Source.server));
      if (snap.docs.isEmpty) {
        debugPrint('getParams: CONFIG collection is empty');
        return null;
      }
      final data = snap.docs.first.data();
      debugPrint('getParams: docId=${snap.docs.first.id}, data=$data');
      return data;
    } catch (e) {
      debugPrint('getParams error: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────
  // GROUP_ASS_NO コレクション（グループ別区域割当て）
  // 各ドキュメント = ある日の一括割当て記録
  // フィールド: groupName, territories (array), timestamp
  // アプリでは最新timestampの1件だけを使用
  // ──────────────────────────────────────────────

  /// AUTOLOCK_LIST から全マンション名を取得し、区域番号(areano)でグループ化して返す
  static Future<Map<String, List<String>>> getAutolockBuildings() async {
    try {
      final snap = await _db
          .collection('AUTOLOCK_LIST')
          .get(const GetOptions(source: Source.server));
      final result = <String, List<String>>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final areano = data['areano'];
        final name = data['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        final key = areano is int
            ? areano.toString()
            : areano is num
                ? areano.toInt().toString()
                : areano?.toString() ?? '';
        if (key.isEmpty) continue;
        result.putIfAbsent(key, () => []).add(name);
      }
      return result;
    } catch (e) {
      debugPrint('getAutolockBuildings error: $e');
      return {};
    }
  }

  /// AUTOLOCK_LIST から区域番号ごとのマンション情報（name + buildno）を取得
  static Future<Map<String, List<Map<String, dynamic>>>> getAutolockBuildingsDetailed() async {
    try {
      final snap = await _db
          .collection('AUTOLOCK_LIST')
          .get(const GetOptions(source: Source.server));
      final result = <String, List<Map<String, dynamic>>>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final areano = data['areano'];
        final buildno = data['buildno'];
        final name = data['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        final key = areano is int
            ? areano.toString()
            : areano is num
                ? areano.toInt().toString()
                : areano?.toString() ?? '';
        if (key.isEmpty) continue;
        final buildnoStr = buildno is int
            ? buildno.toString()
            : buildno is num
                ? buildno.toInt().toString()
                : buildno?.toString() ?? '';
        result.putIfAbsent(key, () => []).add({'name': name, 'buildno': buildnoStr});
      }
      return result;
    } catch (e) {
      debugPrint('getAutolockBuildingsDetailed error: $e');
      return {};
    }
  }

  /// AREA_DATA_AUTOLOCK から住所一覧＋訪問履歴を取得（AREA_DATA_NIGHT と同構造）
  static Future<List<Map<String, dynamic>>> getAutolockCardDataWithHistory(
    String cardName, {
    int historyCount = 5,
  }) async {
    final parsed = _parseCardName(cardName);
    if (parsed == null) return [];

    // 1. 住所マスタ取得（buildNum フィールドを使用）
    var addrSnap = await _db
        .collection('AREA_DATA_AUTOLOCK')
        .where('areaId', isEqualTo: parsed.areaId)
        .where('buildNum', isEqualTo: parsed.sheetId)
        .get();

    if (addrSnap.docs.isEmpty) {
      addrSnap = await _db
          .collection('AREA_DATA_AUTOLOCK')
          .where('areaId', isEqualTo: parsed.areaId.toString())
          .where('buildNum', isEqualTo: parsed.sheetId.toString())
          .get();
    }

    debugPrint('getAutolockCardData: card=$cardName → ${addrSnap.docs.length} docs');
    if (addrSnap.docs.isEmpty) {
      final sample = await _db.collection('AREA_DATA_AUTOLOCK').limit(1).get();
      if (sample.docs.isNotEmpty) {
        debugPrint('sample fields: ${sample.docs.first.data().keys.toList()}');
        debugPrint('sample data: ${sample.docs.first.data()}');
      } else {
        debugPrint('AREA_DATA_AUTOLOCK: コレクションが空です');
      }
      return [];
    }

    // 2. 全アドレスを doc.id をキーで保持（uid 重複問題を回避）
    final docIdToAddr = <String, Map<String, dynamic>>{};
    final docIdToUid = <String, String>{};
    for (final doc in addrSnap.docs) {
      final data = doc.data();
      docIdToAddr[doc.id] = data;
      final uid = data['uid'] as String?;
      if (uid != null && uid.isNotEmpty) docIdToUid[doc.id] = uid;
    }

    // 3. uid が存在するものだけ履歴取得
    final histByUid = <String, List<Map<String, dynamic>>>{};
    final uids = docIdToUid.values.toSet().toList();
    for (int i = 0; i < uids.length; i += 30) {
      final batch = uids.sublist(i, (i + 30).clamp(0, uids.length));
      final histSnap = await _db
          .collection('AREA_DATA_AUTOLOCK_HISTORY')
          .where('uid', whereIn: batch)
          .get();
      for (final doc in histSnap.docs) {
        final data = {'docId': doc.id, ...doc.data()};
        final uid = data['uid'] as String? ?? '';
        if (uid.isNotEmpty) histByUid.putIfAbsent(uid, () => []).add(data);
      }
    }

    // 4. 結合してリストを組み立て
    final results = <Map<String, dynamic>>[];
    for (final entry in docIdToAddr.entries) {
      final docId = entry.key;
      final addr = entry.value;
      final uid = docIdToUid[docId] ?? '';
      final buildName = addr['buildName'] as String? ?? '';
      final roomNumRaw = (addr['roomNum'] ?? addr['room_num'])?.toString() ?? '';
      final houseNum = (addr['houseNum'] ?? addr['house_num'])?.toString() ?? '';
      final roomNum = houseNum.isNotEmpty ? '$roomNumRaw-$houseNum' : roomNumRaw;
      debugPrint('autolock: roomNum=$roomNumRaw houseNum=$houseNum → $roomNum, fields=${addr.keys.toList()}');
      final houseName = addr['houseName'] as String? ?? '';

      String toDateStr(dynamic v) {
        if (v == null) return '';
        if (v is String) return v;
        if (v is Timestamp) {
          final dt = v.toDate().add(const Duration(hours: 9));
          return '${dt.year}/${dt.month}/${dt.day}';
        }
        if (v is DateTime) return '${v.year}/${v.month}/${v.day}';
        return v.toString();
      }

      final histDocs = histByUid[uid] ?? [];
      histDocs.sort((a, b) {
        final aStr = toDateStr(a['startDate'] ?? a['start_date']);
        final bStr = toDateStr(b['startDate'] ?? b['start_date']);
        return bStr.compareTo(aStr);
      });

      final visits = histDocs
          .where((d) {
            final sd = toDateStr(d['startDate'] ?? d['start_date']);
            final ed = toDateStr(d['endDate'] ?? d['end_date']);
            return sd.isNotEmpty && ed.isNotEmpty;
          })
          .take(historyCount)
          .map((d) {
            final sd = toDateStr(d['startDate'] ?? d['start_date']);
            final ed = toDateStr(d['endDate'] ?? d['end_date']);
            return {
              'id': '${sd}_$ed',
              'startDate': sd,
              'endDate': ed,
              'staffName': (d['staffName'] ?? d['staff_name']) as String? ?? '',
              'statusResult': (d['visitResult'] ?? d['status_result']) as String? ?? '',
            };
          })
          .toList();

      results.add({
        'id': docId,
        'uid': uid,
        'addressNumber': roomNum,
        'townName': _floorTag(roomNumRaw),
        'targetName': houseName,
        'note': addr['addressCheck'] as String? ?? '',
        'rj': addr['reject'] as String? ?? '',
        'visits': visits,
      });
    }

    // 階数 → roomNum の順でソート
    results.sort((a, b) {
      final aTown = a['townName'] as String? ?? '';
      final bTown = b['townName'] as String? ?? '';
      if (aTown != bTown) return aTown.compareTo(bTown);
      final aNum = a['addressNumber'] as String? ?? '';
      final bNum = b['addressNumber'] as String? ?? '';
      final an = int.tryParse(aNum);
      final bn = int.tryParse(bNum);
      if (an != null && bn != null) return an.compareTo(bn);
      return aNum.compareTo(bNum);
    });

    return results;
  }

  /// AREA_LIST から全ての区域番号 (areaId) の一覧を取得
  /// [type] を指定した場合は AREA_LIST の type フィールドでフィルタする
  static Future<List<String>> getAllAreaIds({String? type}) async {
    try {
      final Query<Map<String, dynamic>> query = type != null
          ? _db.collection('AREA_LIST').where('type', isEqualTo: type)
          : _db.collection('AREA_LIST');
      final snap = await query.get(const GetOptions(source: Source.server));

      final ids = <int>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        // CSVの構造に基づき、'Number' フィールドまたはドキュメントIDを確認
        var v = data['Number'] ?? data['number'] ?? data['areaId'];
        if (v == null && int.tryParse(doc.id) != null) {
          v = doc.id;
        }

        if (v is int) {
          ids.add(v);
        } else if (v is num) {
          ids.add(v.toInt());
        } else if (v is String) {
          final n = int.tryParse(v);
          if (n != null) ids.add(n);
        }
      }

      if (ids.isEmpty) {
        debugPrint('getAllAreaIds: AREA_LIST is empty, falling back to AREA_DATA_NORMAL');
        return type == null ? _getAllAreaIdsFromDataNormal() : [];
      }

      final sorted = ids.toList()..sort();
      return sorted.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint('getAllAreaIds error: $e');
      return type == null ? _getAllAreaIdsFromDataNormal() : [];
    }
  }

  /// AREA_DATA_NORMAL から全ての区域番号 (areaId) のユニークな一覧を取得 (フォールバック用)
  static Future<List<String>> _getAllAreaIdsFromDataNormal() async {
    try {
      final snap = await _db
          .collection('AREA_DATA_NORMAL')
          .get(const GetOptions(source: Source.server));
      final ids = <int>{};
      for (final doc in snap.docs) {
        final v = doc.data()['areaId'];
        if (v is int) ids.add(v);
        else if (v is num) ids.add(v.toInt());
        else if (v is String) {
          final n = int.tryParse(v);
          if (n != null) ids.add(n);
        }
      }
      final sorted = ids.toList()..sort();
      return sorted.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint('_getAllAreaIdsFromDataNormal error: $e');
      return [];
    }
  }

  /// グループに割り当てる区域番号を保存
  /// 同じ (groupName, startDate) の既存ドキュメントを削除してから新規追加
  static Future<bool> saveGroupTerritories({
    required String groupName,
    required List<String> territories,
    required String startDate,
    required String endDate,
  }) async {
    try {
      // 過去データの表示を必要とせず、毎回新しい番号と日付で更新していくため、
      // 既存の割当てを削除するか、あるいは単に新しい日付で追加する運用とする。
      // ここでは、指定された groupName の既存の全割当てを一旦クリアして上書きする
      final existing = await _db
          .collection('GROUP_ASS_NO')
          .where('groupName', isEqualTo: groupName)
          .get(const GetOptions(source: Source.server));

      final batch = _db.batch();
      for (final doc in existing.docs) {
        batch.delete(doc.reference);
      }

      // 選択された区域番号を追加
      for (final t in territories) {
        final tNum = int.tryParse(t);
        if (tNum == null) continue;
        // ドキュメントIDを固定的なルールにすることで管理しやすくする
        final docRef = _db.collection('GROUP_ASS_NO').doc('${groupName}_${tNum}');
        batch.set(docRef, {
          'groupName': groupName,
          'territories': tNum,
          'startDate': startDate,
          'endDate': endDate,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      debugPrint('saveGroupTerritories: $groupName → $territories ($startDate ~ $endDate)');
      return true;
    } catch (e) {
      debugPrint('saveGroupTerritories error: $e');
      return false;
    }
  }

  /// 指定グループの最新 startDate に紐づく (territories, startDate, endDate) を取得
  ///
  /// [currentOnly] = true のとき、startDate が今日以前のものだけを対象にする。
  /// 最新の startDate がまだ未来の場合はその次（有効な直近）の割当てを返す。
  static Future<({List<String> territories, String? startDate, String? endDate})>
      getLatestGroupAssignment(String groupName, {String type = 'NORMAL', bool currentOnly = false}) async {
    try {
      final snap = await _db
          .collection('GROUP_ASS_NO')
          .where('groupName', isEqualTo: groupName)
          .get(const GetOptions(source: Source.server));

      if (snap.docs.isEmpty) {
        return (territories: <String>[], startDate: null, endDate: null);
      }

      bool matchesType(Map<String, dynamic> data) {
        final t = (data['type'] ?? 'NORMAL').toString().trim();
        return t == type;
      }

      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);

      String? latestStartStr;
      DateTime? latestDate;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (!matchesType(data)) continue;
        final sd = (data['startDate'] ?? '').toString().trim();
        final dt = _parseDate(sd);
        if (dt == null) continue;
        // currentOnly: 今日より未来の startDate はスキップ
        if (currentOnly && dt.isAfter(todayDate)) continue;
        if (latestDate == null || dt.isAfter(latestDate)) {
          latestDate = dt;
          latestStartStr = sd;
        }
      }
      if (latestStartStr == null) {
        return (territories: <String>[], startDate: null, endDate: null);
      }

      final territories = <String>[];
      String? endDate;
      for (final doc in snap.docs) {
        final data = doc.data();
        if (!matchesType(data)) continue;
        if ((data['startDate'] ?? '').toString().trim() == latestStartStr) {
          final t = data['territories']?.toString() ?? '';
          if (t.isNotEmpty) territories.add(t);
          endDate ??= (data['endDate'] ?? '').toString();
        }
      }
      territories.sort((a, b) {
        final na = int.tryParse(a);
        final nb = int.tryParse(b);
        if (na != null && nb != null) return na.compareTo(nb);
        return a.compareTo(b);
      });
      return (territories: territories, startDate: latestStartStr, endDate: endDate);
    } catch (e) {
      debugPrint('getLatestGroupAssignment error: $e');
      return (territories: <String>[], startDate: null, endDate: null);
    }
  }

  /// 全グループ名を取得 (GROUP_LIST コレクションから取得)
  static Future<List<String>> getGroupNames() async {
    try {
      final snap = await _db
          .collection('GROUP_LIST')
          .get(const GetOptions(source: Source.server));
      
      final names = <String>{};
      for (final doc in snap.docs) {
        // ドキュメントIDをグループ名とするか、フィールド 'name' を取るか
        // 一般的にはドキュメントIDまたは 'groupName' フィールド
        final data = doc.data();
        final name = data['groupName'] as String? ?? doc.id;
        if (name.isNotEmpty) names.add(name);
      }
      final sorted = names.toList()..sort();
      return sorted;
    } catch (e) {
      debugPrint('getGroupNames error: $e');
      return [];
    }
  }

  /// 全グループの現在の割当て状況を取得 (territoryNumber -> groupName)
  static Future<Map<String, String>> getAllLatestAssignments({
    String type = 'NORMAL',
  }) async {
    try {
      final snap = await _db
          .collection('GROUP_ASS_NO')
          .get(const GetOptions(source: Source.server));

      final Map<String, String> results = {};
      for (final doc in snap.docs) {
        final data = doc.data();
        final docType = (data['type'] ?? 'NORMAL').toString().trim();
        if (docType != type) continue;
        final group = data['groupName']?.toString() ?? '';
        final territory = data['territories']?.toString() ?? '';
        if (group.isNotEmpty && territory.isNotEmpty) {
          results[territory] = group;
        }
      }
      return results;
    } catch (e) {
      debugPrint('getAllLatestAssignments error: $e');
      return {};
    }
  }

  /// S-13用: 全区域の割当て一覧を返す（区域番号・監督名・開始日付・終了日付）
  /// type=NORMAL のみ対象。区域ごとに最新の startDate のレコードを取得し、
  /// USER_LIST の status4='SV' から各グループの監督名を結合する。
  static Future<List<Map<String, dynamic>>> getTerritoryTableData() async {
    try {
      final snap = await _db
          .collection('GROUP_ASS_NO')
          .get(const GetOptions(source: Source.server));

      final svSnap = await _db
          .collection('USER_LIST')
          .where('status4', isEqualTo: 'SV')
          .get();
      final supervisorByGroup = <String, String>{};
      for (final doc in svSnap.docs) {
        final d = doc.data();
        final g = (d['group'] as String? ?? '').trim();
        final n = (d['name'] as String? ?? '').trim();
        if (g.isNotEmpty && n.isNotEmpty) supervisorByGroup[g] = n;
      }

      final latestByTerritory = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        if ((data['type'] ?? 'NORMAL').toString().trim() != 'NORMAL') continue;
        final territory = data['territories']?.toString() ?? '';
        if (territory.isEmpty) continue;
        final sd = (data['startDate'] ?? '').toString().trim();
        if (!latestByTerritory.containsKey(territory)) {
          latestByTerritory[territory] = data;
        } else {
          final existingDt = _parseDate(latestByTerritory[territory]!['startDate']?.toString() ?? '');
          final newDt = _parseDate(sd);
          if (newDt != null && (existingDt == null || newDt.isAfter(existingDt))) {
            latestByTerritory[territory] = data;
          }
        }
      }

      final rows = latestByTerritory.entries.map((e) {
        final data = e.value;
        final groupName = (data['groupName'] ?? '').toString();
        return {
          'territory': e.key,
          'groupName': groupName,
          'supervisorName': supervisorByGroup[groupName] ?? '',
          'startDate': (data['startDate'] ?? '').toString(),
          'endDate': (data['endDate'] ?? '').toString(),
        };
      }).toList();

      rows.sort((a, b) {
        final na = int.tryParse(a['territory'] as String);
        final nb = int.tryParse(b['territory'] as String);
        if (na != null && nb != null) return na.compareTo(nb);
        return (a['territory'] as String).compareTo(b['territory'] as String);
      });

      return rows;
    } catch (e) {
      debugPrint('getTerritoryTableData error: $e');
      return [];
    }
  }

  /// "yyyy/M/d" 形式の文字列を DateTime に変換するヘルパー
  /// 全グループの区域割当てを一旦クリアして一括保存
  static Future<bool> saveAllGroupAssignments({
    required Map<String, String?> assignments, // territory -> groupName
    required String startDate,
    required String endDate,
    String type = 'NORMAL',
  }) async {
    try {
      // 1. 既存の割当てのうち、同じ type のものだけを削除
      final existing = await _db.collection('GROUP_ASS_NO').get();
      final batch = _db.batch();
      for (final doc in existing.docs) {
        final docType = (doc.data()['type'] ?? 'NORMAL').toString().trim();
        if (docType == type) {
          batch.delete(doc.reference);
        }
      }

      // 2. 新しい割当てを保存（type を付与し、ID は type でプレフィックス）
      assignments.forEach((territory, groupName) {
        if (groupName != null && groupName.isNotEmpty && groupName != '未割当て') {
          final tNum = int.tryParse(territory);
          if (tNum != null) {
            final docRef = _db
                .collection('GROUP_ASS_NO')
                .doc('${type}_${groupName}_${tNum}');
            batch.set(docRef, {
              'groupName': groupName,
              'territories': tNum,
              'startDate': startDate,
              'endDate': endDate,
              'type': type,
              'timestamp': FieldValue.serverTimestamp(),
            });
          }
        }
      });

      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('saveAllGroupAssignments error: $e');
      return false;
    }
  }

  static DateTime? _parseDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      final parts = dateStr.split('/');
      if (parts.length == 3) {
        return DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
      }
    } catch (e) {
      debugPrint('Firestore: Error parsing date "$dateStr": $e');
    }
    return null;
  }

  static Future<List<String>> getTerritoriesForGroup(
    String groupName, {
    String type = 'NORMAL',
    bool currentOnly = false,
  }) async {
    debugPrint('Firestore: getTerritoriesForGroup started for group="$groupName" type="$type" currentOnly=$currentOnly');

    try {
      final snap = await _db
          .collection('GROUP_ASS_NO')
          .get(const GetOptions(source: Source.server));
      debugPrint('Firestore: Fetched ${snap.docs.length} total documents from GROUP_ASS_NO (source=server)');

      if (snap.docs.isEmpty) return [];

      final normalizedGroupName = groupName.trim();
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      String? latestStartDateStr;
      DateTime? latestDate;

      // 1. 指定されたグループの 指定 type の中から「最新の日付」を特定する
      //    currentOnly=true の場合は今日以前の startDate のみ対象
      for (final doc in snap.docs) {
        final data = doc.data();
        final g = data['groupName']?.toString().trim() ?? '';
        final docType = (data['type'] ?? 'NORMAL').toString().trim();
        if (docType != type) continue;

        if (g == normalizedGroupName) {
          final sdStr = (data['startDate'] ?? data['start_date'])?.toString().trim();
          final date = _parseDate(sdStr);

          if (date != null) {
            if (currentOnly && date.isAfter(todayDate)) continue;
            if (latestDate == null || date.isAfter(latestDate)) {
              latestDate = date;
              latestStartDateStr = sdStr;
            }
          }
        }
      }

      if (latestStartDateStr == null) {
        debugPrint('Firestore: No valid startDate found for group "$normalizedGroupName". Falling back to timestamp...');
        return _getTerritoriesByTimestamp(snap.docs, normalizedGroupName, type: type);
      }
      
      debugPrint('Firestore: Latest startDate for $normalizedGroupName identified as "$latestStartDateStr"');

      // 2. その「最新の日付文字列」に一致するレコードをすべて抽出
      final territories = <String>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final g = data['groupName']?.toString().trim() ?? '';
        final sdStr = (data['startDate'] ?? data['start_date'])?.toString().trim();
        final docType = (data['type'] ?? 'NORMAL').toString().trim();
        if (docType != type) continue;

        if (g == normalizedGroupName && sdStr == latestStartDateStr) {
          final t = data['territories']?.toString() ?? '';
          if (t.isNotEmpty) territories.add(t);
        }
      }

      territories.sort((a, b) {
        final na = int.tryParse(a);
        final nb = int.tryParse(b);
        if (na != null && nb != null) return na.compareTo(nb);
        return a.compareTo(b);
      });
      
      debugPrint('Firestore: Result territories for $normalizedGroupName: $territories');
      return territories;
    } catch (e) {
      debugPrint('Firestore: getTerritoriesForGroup ERROR: $e');
      return [];
    }
  }

  /// 従来の timestamp ベースで最新を取得する内部メソッド
  static List<String> _getTerritoriesByTimestamp(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String groupName, {
    String type = 'NORMAL',
  }) {
    final groupDocs = docs.where((doc) {
      final data = doc.data();
      final g = data['groupName']?.toString().trim() ?? '';
      final docType = (data['type'] ?? 'NORMAL').toString().trim();
      return g == groupName && docType == type;
    }).toList();

    if (groupDocs.isEmpty) return [];

    groupDocs.sort((a, b) {
      final tsA = a.data()['timestamp'] as Timestamp?;
      final tsB = b.data()['timestamp'] as Timestamp?;
      if (tsA == null && tsB == null) return 0;
      if (tsA == null) return 1;
      if (tsB == null) return -1;
      return tsB.compareTo(tsA);
    });

    final latestTs = groupDocs.first.data()['timestamp'] as Timestamp?;
    if (latestTs == null) return [];

    final territories = <String>[];
    for (final doc in groupDocs) {
      final ts = doc.data()['timestamp'] as Timestamp?;
      if (ts == null || ts.compareTo(latestTs) != 0) break;
      final t = doc.data()['territories']?.toString() ?? '';
      if (t.isNotEmpty) territories.add(t);
    }
    return territories;
  }

  // ──────────────────────────────────────────────
  // nightTerritories コレクション
  // ──────────────────────────────────────────────

  static Future<List<String>> getNightTerritories() async {
    try {
      final doc = await _db.collection('nightTerritories').doc('config').get();
      if (!doc.exists) return [];
      final data = doc.data()!;
      final list = data['territories'];
      if (list is List) return list.cast<String>();
      return [];
    } catch (e) {
      debugPrint('getNightTerritories error: $e');
      return [];
    }
  }

  // ──────────────────────────────────────────────
  // CARD_ASSIGNMENTS コレクション（カード割当て）
  // ──────────────────────────────────────────────

  /// areaId/sheetId フィールドがあればそれを使い、古い cardName フィールドにフォールバック
  /// CARD_ASSIGNMENTS から "areaId-sheetId" 形式のカード名を復元する
  /// 新データ: territoryNumber="2", cardName="1" → "2-1"
  /// 旧データ: cardName="2-1" → "2-1"（後方互換）
  static String cardNameFromDoc(Map<String, dynamic> data) {
    final territoryNumber = data['territoryNumber']?.toString() ?? '';
    final cardName = _normCardName(data['cardName']?.toString() ?? '');
    // cardName がシートIDのみ（数字のみ、ハイフンなし）なら territoryNumber と結合
    if (territoryNumber.isNotEmpty && cardName.isNotEmpty && !cardName.contains('-')) {
      return '$territoryNumber-$cardName';
    }
    return cardName;
  }

  static Future<List<Map<String, dynamic>>> getAssignmentsForGroup(String groupName) async {
    final snap = await _db
        .collection('CARD_ASSIGNMENTS')
        .where('groupName', isEqualTo: groupName)
        .get();
    return snap.docs.map((d) => d.data()).toList();
  }

  static Future<List<Map<String, dynamic>>> getAssignmentsForTerritory(
    String groupName,
    String territoryNumber, {
    bool isNight = false,
  }) async {
    final targetGroup = isNight ? '夜間区域' : groupName;
    final parsedTerritoryNumber = int.tryParse(territoryNumber) ?? territoryNumber;

    Query<Map<String, dynamic>> query = _db
        .collection('CARD_ASSIGNMENTS')
        .where('territoryNumber', isEqualTo: parsedTerritoryNumber);
    if (!isNight) {
      query = query.where('groupName', isEqualTo: targetGroup);
    }
    final snap = await query.get(const GetOptions(source: Source.server));
    return snap.docs.map((d) => d.data()).toList();
  }

  static Future<List<String>> getAssignedCardNamesForUser(String userName) async {
    final snap = await _db
        .collection('CARD_ASSIGNMENTS')
        .where('memberName', isEqualTo: userName.trim())
        .get(const GetOptions(source: Source.server));

    if (snap.docs.isEmpty) return [];

    return snap.docs
        .map((d) => cardNameFromDoc(d.data()))
        .where((n) => n.isNotEmpty)
        .toList();
  }

  /// グループ区域に設定されたカード名一覧を取得（memberName == 'グループ区域'）
  static Future<List<String>> getGroupAreaCardNames(String groupName) async {
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _db
            .collection('CARD_ASSIGNMENTS')
            .where('memberName', isEqualTo: 'グループ区域')
            .get(const GetOptions(source: Source.cache));
        if (snap.docs.isEmpty) throw Exception('cache empty');
      } catch (_) {
        snap = await _db
            .collection('CARD_ASSIGNMENTS')
            .where('memberName', isEqualTo: 'グループ区域')
            .get(const GetOptions(source: Source.server));
      }

      // 指定グループのドキュメントのみに絞り込む
      final docs = snap.docs
          .where((doc) => (doc.data()['groupName']?.toString() ?? '') == groupName)
          .toList();

      if (docs.isEmpty) return [];

      // カードごとに最新 startDate を特定
      final latestDatePerCard = <String, DateTime>{};
      final latestStrPerCard = <String, String>{};
      for (final doc in docs) {
        final data = doc.data();
        final cardName = cardNameFromDoc(data);
        final sdStr = (data['startDate'] ?? data['start_date'])?.toString().trim();
        final date = _parseDate(sdStr);
        if (cardName.isEmpty || date == null) continue;
        if (!latestDatePerCard.containsKey(cardName) || date.isAfter(latestDatePerCard[cardName]!)) {
          latestDatePerCard[cardName] = date;
          latestStrPerCard[cardName] = sdStr!;
        }
      }

      final cardNames = <String>{};
      for (final doc in docs) {
        final data = doc.data();
        final cardName = cardNameFromDoc(data);
        final sdStr = (data['startDate'] ?? data['start_date'])?.toString().trim();
        if (cardName.isNotEmpty && sdStr != null && sdStr == latestStrPerCard[cardName]) {
          cardNames.add(cardName);
        }
      }

      // startDate がないデータへのフォールバック
      if (cardNames.isEmpty) {
        for (final doc in docs) {
          final cardName = cardNameFromDoc(doc.data());
          if (cardName.isNotEmpty) cardNames.add(cardName);
        }
      }

      final sorted = cardNames.toList()
        ..sort((a, b) {
          final pa = _parseCardName(a);
          final pb = _parseCardName(b);
          if (pa != null && pb != null) {
            if (pa.areaId != pb.areaId) return pa.areaId.compareTo(pb.areaId);
            return pa.sheetId.compareTo(pb.sheetId);
          }
          return a.compareTo(b);
        });
      return sorted;
    } catch (e) {
      debugPrint('getGroupAreaCardNames error: $e');
      return [];
    }
  }

  static Future<void> saveAssignment({
    required String groupName,
    required String territoryNumber,
    required String cardName,
    required String memberName,
    String? startDate,
    String? endDate,
  }) async {
    final normalized = _normCardName(cardName);
    final parts = normalized.split('-');
    final areaId = parts[0];
    final sheetId = parts.length > 1 ? parts[1] : '1';
    final latestDocId = '${groupName}_${areaId}_$sheetId';

    final newData = {
      'groupName': groupName,
      'territoryNumber': int.tryParse(areaId) ?? areaId,
      'cardName': int.tryParse(sheetId) ?? sheetId,
      'memberName': memberName,
      'startDate': startDate,
      'endDate': endDate,
      'timestamp': FieldValue.serverTimestamp(),
    };

    // テリトリーナンバーとカードナンバーで既存ドキュメントを検索し
    // 新しい担当者の保存時刻より古いものをHISTORYへ移動
    final now = DateTime.now();
    final existingSnap = await _db
        .collection('CARD_ASSIGNMENTS')
        .where('groupName', isEqualTo: groupName)
        .where('territoryNumber', isEqualTo: int.tryParse(areaId) ?? areaId)
        .where('cardName', isEqualTo: int.tryParse(sheetId) ?? sheetId)
        .get(const GetOptions(source: Source.server));

    final tsMillis = now.millisecondsSinceEpoch;
    final moveBatch = _db.batch();
    int moveCount = 0;
    for (int i = 0; i < existingSnap.docs.length; i++) {
      final doc = existingSnap.docs[i];
      final docTs = doc.data()['timestamp'];
      final docTime = docTs is Timestamp ? docTs.toDate() : null;
      if (docTime == null || docTime.isBefore(now)) {
        final historyDocId = '${groupName}_${areaId}_${sheetId}_${tsMillis + i}';
        moveBatch.set(_db.collection('CARD_ASSIGNMENTS_HISTORY').doc(historyDocId), doc.data());
        moveBatch.delete(doc.reference);
        moveCount++;
      }
    }
    if (moveCount > 0) await moveBatch.commit();
    await _db.collection('CARD_ASSIGNMENTS').doc(latestDocId).set(newData);
  }

  static Future<void> saveAssignmentsBatch(
    String groupName,
    String territoryNumber,
    List<List<dynamic>> rows, {
    bool isNight = false,
    String? startDate,
    String? endDate,
  }) async {
    // startDate が未指定の場合は、今日の日付をデフォルトとする
    final effectiveStartDate = startDate ?? "${DateTime.now().year}/${DateTime.now().month}/${DateTime.now().day}";
    
    debugPrint('Firestore: saveAssignmentsBatch started. Group: $groupName, Territory: $territoryNumber, Rows: ${rows.length}, Start: $startDate (Effective: $effectiveStartDate)');
    
    final targetGroup = isNight ? '夜間区域' : groupName;
    
    // 一時的な通信エラー (UNAVAILABLE) の場合、最大2回リトライする
    int retryCount = 0;
    const maxRetries = 2;

    while (retryCount <= maxRetries) {
      try {
        // バッチに含めるカード情報を収集
        final List<({String areaId, String sheetId, String memberName})> cardEntries = [];
        for (final row in rows) {
          if (row.length >= 2) {
            final cardName = row[0].toString().trim();
            final memberName = row[1].toString().trim();
            if (memberName.isEmpty) continue;
            final normalized = _normCardName(cardName);
            final parts = normalized.split('-');
            final areaId = parts[0];
            final sheetId = parts.length > 1 ? parts[1] : '1';
            cardEntries.add((areaId: areaId, sheetId: sheetId, memberName: memberName));
          }
        }

        if (cardEntries.isEmpty) return;

        // この区域の既存ドキュメントをフィールドクエリでまとめて取得（doc IDフォーマット不問）
        final now = DateTime.now();
        final parsedTerritoryNumber = int.tryParse(territoryNumber) ?? territoryNumber;
        final existingSnap = await _db
            .collection('CARD_ASSIGNMENTS')
            .where('groupName', isEqualTo: targetGroup)
            .where('territoryNumber', isEqualTo: parsedTerritoryNumber)
            .get(const GetOptions(source: Source.server));

        // cardName ごとに既存ドキュメントをグループ化
        final existingByCard = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
        for (final doc in existingSnap.docs) {
          final data = doc.data();
          final cn = int.tryParse(data['cardName']?.toString() ?? '')?.toString()
              ?? data['cardName']?.toString()
              ?? '';
          if (cn.isNotEmpty) {
            existingByCard.putIfAbsent(cn, () => []).add(doc);
          }
        }

        final batch = _db.batch();
        final tsMillis = now.millisecondsSinceEpoch;

        for (int i = 0; i < cardEntries.length; i++) {
          final e = cardEntries[i];
          final latestDocId = '${targetGroup}_${e.areaId}_${e.sheetId}';

          // 同カードのドキュメントの中で、新しい担当者の保存時刻より古いものをHISTORYへ移動
          final oldDocs = existingByCard[e.sheetId] ?? [];
          for (int j = 0; j < oldDocs.length; j++) {
            final oldDoc = oldDocs[j];
            final docTs = oldDoc.data()['timestamp'];
            final docTime = docTs is Timestamp ? docTs.toDate() : null;
            if (docTime == null || docTime.isBefore(now)) {
              final historyDocId = '${targetGroup}_${e.areaId}_${e.sheetId}_${tsMillis + i * 100 + j}';
              batch.set(
                _db.collection('CARD_ASSIGNMENTS_HISTORY').doc(historyDocId),
                oldDoc.data(),
              );
              batch.delete(oldDoc.reference);
            }
          }

          // 最新ドキュメントを固定IDで書き込み
          batch.set(_db.collection('CARD_ASSIGNMENTS').doc(latestDocId), {
            'groupName': targetGroup,
            'territoryNumber': int.tryParse(e.areaId) ?? e.areaId,
            'cardName': int.tryParse(e.sheetId) ?? e.sheetId,
            'memberName': e.memberName,
            'startDate': effectiveStartDate,
            'endDate': endDate,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }

        debugPrint('Firestore: Committing batch for ${cardEntries.length} cards...');
        await batch.commit().timeout(const Duration(seconds: 15));
        debugPrint('Firestore: Batch commit successful');
        return; // 成功したら終了
      } catch (e) {
        final errorStr = e.toString().toLowerCase();
        if ((errorStr.contains('unavailable') || errorStr.contains('shutdown')) && retryCount < maxRetries) {
          retryCount++;
          debugPrint('Firestore: saveAssignmentsBatch failed (UNAVAILABLE), retrying ($retryCount/$maxRetries)...');
          await Future.delayed(Duration(seconds: 2 * retryCount));
          continue;
        }
        debugPrint('Firestore: saveAssignmentsBatch ERROR: $e');
        rethrow;
      }
    }
  }

  static Future<void> clearAllAssignments() async {
    final snap = await _db.collection('CARD_ASSIGNMENTS').get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  static Stream<List<Map<String, dynamic>>> watchAssignments(String groupName) {
    return _db
        .collection('CARD_ASSIGNMENTS')
        .where('groupName', isEqualTo: groupName)
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  // ──────────────────────────────────────────────
  // AREA_DATA_NORMAL コレクション（区域カード - フラット構造）
  //
  // 各ドキュメント = 1住所 × 1訪問期間
  // フィールド: areaId, sheetId, addressNumber, townName,
  //   chome, block, targetName, note, rj,
  //   startDate, endDate, staffName, statusResult
  //
  // カード名 = "areaId-sheetId" (例: "43-3")
  // ──────────────────────────────────────────────

  /// カード名をareaIdとsheetIdに分解
  static ({int areaId, int sheetId})? _parseCardName(String cardName) {
    final normalized = _normCardName(cardName);
    final parts = normalized.split('-');
    if (parts.length < 2) return null;
    final areaId = int.tryParse(parts[0]);
    final sheetId = int.tryParse(parts[1]);
    if (areaId == null || sheetId == null) return null;
    return (areaId: areaId, sheetId: sheetId);
  }

  /// roomNum から階数タグを生成（例: "101"→"1F", "B201"→"2F", "1001"→"10F"）
  static String _floorTag(String roomNumRaw) {
    final digits = roomNumRaw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 1) return '${digits}F';
    if (digits.length == 3) return '${digits[0]}F';
    if (digits.length == 4) return '${digits.substring(0, 2)}F';
    return roomNumRaw;
  }

  /// カード内の全ドキュメントを一括取得
  static Future<List<Map<String, dynamic>>> _getCardDocuments(String cardName) async {
    final parsed = _parseCardName(cardName);
    if (parsed == null) return [];
    final snap = await _db
        .collection('AREA_DATA_NORMAL')
        .where('areaId', isEqualTo: parsed.areaId)
        .where('sheetId', isEqualTo: parsed.sheetId)
        .get();
    return snap.docs.map((d) => {'docId': d.id, ...d.data()}).toList();
  }

  /// ドキュメント群を住所ごとにグループ化し、訪問履歴付きで返す
  static List<Map<String, dynamic>> _groupByAddress(
    List<Map<String, dynamic>> docs, {
    int historyCount = 5,
  }) {
    // addressNumber でグループ化
    final grouped = <int, List<Map<String, dynamic>>>{};
    for (final doc in docs) {
      final addrNum = doc['addressNumber'] as int? ?? 0;
      grouped.putIfAbsent(addrNum, () => []).add(doc);
    }

    final results = <Map<String, dynamic>>[];
    final sortedKeys = grouped.keys.toList()..sort();

    for (final addrNum in sortedKeys) {
      final addrDocs = grouped[addrNum]!;

      // startDate降順でソート（新しい訪問が先頭）
      addrDocs.sort((a, b) {
        final aDate = a['startDate'] as String? ?? '';
        final bDate = b['startDate'] as String? ?? '';
        return bDate.compareTo(aDate);
      });

      // 最新のドキュメントから住所情報を取得
      final latest = addrDocs.first;

      // 訪問履歴を構築
      final visits = addrDocs
          .where((d) =>
              (d['startDate'] as String? ?? '').isNotEmpty &&
              (d['endDate'] as String? ?? '').isNotEmpty)
          .take(historyCount)
          .map((d) => {
                'id': '${d['startDate']}_${d['endDate']}',
                'startDate': d['startDate'] as String? ?? '',
                'endDate': d['endDate'] as String? ?? '',
                'staffName': d['staffName'] as String? ?? '',
                'statusResult': d['statusResult'] as String? ?? '',
              })
          .toList();

      results.add({
        'id': addrNum.toString(),
        'addressNumber': addrNum,
        'townName': latest['townName'] as String? ?? '',
        'chome': latest['chome'] as String? ?? '',
        'block': latest['block'] as String? ?? '',
        'targetName': latest['targetName'] as String? ?? '',
        'note': latest['note'] as String? ?? '',
        'rj': latest['rj'] as String? ?? '',
        'visits': visits,
      });
    }
    return results;
  }

  /// カード一覧を取得（区域番号でフィルタ）→ ユニークな sheetId を返す
  static Future<List<Map<String, dynamic>>> getCardsForTerritory(String territoryNumber) async {
    final areaId = int.tryParse(territoryNumber);
    if (areaId == null) return [];

    final snap = await _db
        .collection('AREA_DATA_NORMAL')
        .where('areaId', isEqualTo: areaId)
        .get(const GetOptions(source: Source.server));

    // ユニークな sheetId を収集
    final sheetIds = <int>{};
    for (final doc in snap.docs) {
      final sid = doc.data()['sheetId'];
      if (sid is int) sheetIds.add(sid);
      else if (sid is num) sheetIds.add(sid.toInt());
    }

    final cards = sheetIds.map((sid) => {
          'id': '$areaId-$sid',
          'areaId': areaId,
          'sheetId': sid,
        }).toList();
    cards.sort((a, b) => (a['sheetId'] as int).compareTo(b['sheetId'] as int));
    return cards;
  }

  /// 指定カード名のみの最新割当てをドキュメントIDで直接取得（履歴ドキュメントをスキップ）
  /// ドキュメントID形式: ${groupName}_${territoryNumber}_${cardName}
  /// 戻り値: cardName -> memberName
  static Future<Map<String, String>> getLatestAssignmentsByDocId(
    String groupName,
    String territoryNumber,
    List<String> cardNames,
  ) async {
    final docs = await getLatestAssignmentDocsByDocId(groupName, territoryNumber, cardNames);
    final results = <String, String>{};
    docs.forEach((cardName, data) {
      final memberName = data['memberName']?.toString() ?? '';
      if (memberName.isNotEmpty) {
        results[cardName] = memberName;
      }
    });
    return results;
  }

  /// 指定カード名のみの最新割当てドキュメントをドキュメントIDで直接取得（履歴ドキュメントをスキップ）
  /// ドキュメントID形式: ${groupName}_${territoryNumber}_${cardName}
  /// 戻り値: cardName -> 完全なドキュメントデータ
  static Future<Map<String, Map<String, dynamic>>> getLatestAssignmentDocsByDocId(
    String groupName,
    String territoryNumber,
    List<String> cardNames,
  ) async {
    if (cardNames.isEmpty) return {};

    final results = <String, Map<String, dynamic>>{};

    for (int i = 0; i < cardNames.length; i += 30) {
      final batch = cardNames.sublist(i, (i + 30).clamp(0, cardNames.length));
      final docIds = batch.map((c) {
        final parts = _normCardName(c).split('-');
        final areaId = parts[0];
        final sheetId = parts.length > 1 ? parts[1] : '1';
        return '${groupName}_${areaId}_$sheetId';
      }).toList();

      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await _db
            .collection('CARD_ASSIGNMENTS')
            .where(FieldPath.documentId, whereIn: docIds)
            .get(const GetOptions(source: Source.cache));
        if (snap.docs.isEmpty) throw Exception('cache empty');
      } catch (_) {
        snap = await _db
            .collection('CARD_ASSIGNMENTS')
            .where(FieldPath.documentId, whereIn: docIds)
            .get(const GetOptions(source: Source.server));
      }

      for (final doc in snap.docs) {
        final data = doc.data();
        final cardName = cardNameFromDoc(data);
        if (cardName.isNotEmpty) {
          results[cardName] = data;
        }
      }
    }
    return results;
  }

  /// カード名リストからカード情報を取得（フラット構造では名前から導出）
  static Future<List<Map<String, dynamic>>> getCardsByNames(List<String> cardNames) async {
    return cardNames.map((name) {
      final parsed = _parseCardName(name);
      return {
        'id': _normCardName(name),
        'areaId': parsed?.areaId,
        'sheetId': parsed?.sheetId,
      };
    }).toList();
  }

  /// 全カード名一覧を取得
  static Future<List<String>> getAllCardNames() async {
    final snap = await _db.collection('AREA_DATA_NORMAL').get();
    final names = <String>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final areaId = data['areaId'];
      final sheetId = data['sheetId'];
      if (areaId != null && sheetId != null) {
        names.add('$areaId-$sheetId');
      }
    }
    final sorted = names.toList()..sort((a, b) {
      final pa = _parseCardName(a);
      final pb = _parseCardName(b);
      if (pa != null && pb != null) {
        if (pa.areaId != pb.areaId) return pa.areaId.compareTo(pb.areaId);
        return pa.sheetId.compareTo(pb.sheetId);
      }
      return a.compareTo(b);
    });
    return sorted;
  }

  /// カード内の住所一覧を取得（訪問履歴なし、ユニーク住所のみ）
  static Future<List<Map<String, dynamic>>> getAddresses(String cardName) async {
    final docs = await _getCardDocuments(cardName);
    // addressNumber でユニーク化（最新ドキュメントの情報を使用）
    final seen = <int>{};
    final results = <Map<String, dynamic>>[];

    // startDate降順でソートして最新情報を優先
    docs.sort((a, b) {
      final aDate = a['startDate'] as String? ?? '';
      final bDate = b['startDate'] as String? ?? '';
      return bDate.compareTo(aDate);
    });

    for (final doc in docs) {
      final addrNum = doc['addressNumber'] as int? ?? 0;
      if (seen.contains(addrNum)) continue;
      seen.add(addrNum);
      results.add({
        'id': addrNum.toString(),
        'addressNumber': addrNum,
        'townName': doc['townName'] as String? ?? '',
        'chome': doc['chome'] as String? ?? '',
        'block': doc['block'] as String? ?? '',
        'targetName': doc['targetName'] as String? ?? '',
        'note': doc['note'] as String? ?? '',
        'rj': doc['rj'] as String? ?? '',
      });
    }
    results.sort((a, b) => (a['addressNumber'] as int).compareTo(b['addressNumber'] as int));
    return results;
  }

  /// カード全住所の訪問履歴（直近N期間分）を一括取得
  static Future<List<Map<String, dynamic>>> getCardDataWithHistory(
    String cardName, {
    int historyCount = 5,
  }) async {
    final docs = await _getCardDocuments(cardName);
    return _groupByAddress(docs, historyCount: historyCount);
  }

  /// カード全住所の現在期間の訪問データを一括取得
  static Future<List<Map<String, dynamic>>> getCardDataForPeriod(
    String cardName,
    String startDate,
    String endDate,
  ) async {
    final allData = await getCardDataWithHistory(cardName);
    final visitId = '${startDate}_$endDate';

    return allData.map((addr) {
      final visits = addr['visits'] as List<Map<String, dynamic>>? ?? [];
      final current = visits.where((v) => v['id'] == visitId).toList();
      return {
        ...addr,
        'currentVisit': current.isNotEmpty ? current.first : null,
      };
    }).toList();
  }

  /// 訪問ステータスを更新（AREA_DATA_NORMAL にドキュメントを追加 or 更新）
  static Future<void> updateVisitStatus({
    required String cardName,
    required String addressId,
    required String startDate,
    required String endDate,
    required String staffName,
    required String statusResult,
  }) async {
    final parsed = _parseCardName(cardName);
    if (parsed == null) return;
    final addressNumber = int.tryParse(addressId);
    if (addressNumber == null) return;

    // 同じ住所 × 同じ期間のドキュメントを検索
    final snap = await _db
        .collection('AREA_DATA_NORMAL')
        .where('areaId', isEqualTo: parsed.areaId)
        .where('sheetId', isEqualTo: parsed.sheetId)
        .where('addressNumber', isEqualTo: addressNumber)
        .where('startDate', isEqualTo: startDate)
        .where('endDate', isEqualTo: endDate)
        .limit(1)
        .get();

    if (snap.docs.isNotEmpty) {
      // 既存ドキュメントを更新
      await snap.docs.first.reference.update({
        'staffName': staffName,
        'statusResult': statusResult,
      });
    } else {
      // 新規ドキュメントを作成（住所情報は既存ドキュメントからコピー）
      final addrSnap = await _db
          .collection('AREA_DATA_NORMAL')
          .where('areaId', isEqualTo: parsed.areaId)
          .where('sheetId', isEqualTo: parsed.sheetId)
          .where('addressNumber', isEqualTo: addressNumber)
          .limit(1)
          .get();

      Map<String, dynamic> baseData;
      if (addrSnap.docs.isNotEmpty) {
        baseData = Map<String, dynamic>.from(addrSnap.docs.first.data());
        baseData.remove('docId');
      } else {
        baseData = {
          'areaId': parsed.areaId,
          'sheetId': parsed.sheetId,
          'addressNumber': addressNumber,
          'townName': '',
          'chome': '',
          'block': '',
          'targetName': '',
          'note': '',
          'rj': '',
        };
      }

      baseData['startDate'] = startDate;
      baseData['endDate'] = endDate;
      baseData['staffName'] = staffName;
      baseData['statusResult'] = statusResult;

      await _db.collection('AREA_DATA_NORMAL').add(baseData);
    }
    debugPrint('updateVisitStatus: $cardName addr=$addressId status=$statusResult');
  }

  // ──────────────────────────────────────────────
  // リアルタイムリスナー（AREA_DATA_NORMAL）
  // ──────────────────────────────────────────────

  /// カード内のデータ変更をリアルタイムで監視
  static Stream<List<Map<String, dynamic>>> watchAddresses(String cardName) {
    final parsed = _parseCardName(cardName);
    if (parsed == null) return Stream.value([]);

    return _db
        .collection('AREA_DATA_NORMAL')
        .where('areaId', isEqualTo: parsed.areaId)
        .where('sheetId', isEqualTo: parsed.sheetId)
        .snapshots()
        .map((snap) {
      final docs = snap.docs.map((d) => {'docId': d.id, ...d.data()}).toList();
      return _groupByAddress(docs);
    });
  }

  // ──────────────────────────────────────────────
  // AREA_DATA_NIGHT / AREA_DATA_NIGHT_HISTORY
  // 夜間区域カード
  //
  // AREA_DATA_NIGHT フィールド:
  //   uid, type, area_id, sheet_id, town_name, chome, gaiku, house_num,
  //   build_name, room_num, house_name, reject, address_check
  //
  // AREA_DATA_NIGHT_HISTORY フィールド:
  //   uid, type, start_date, end_date, visit_result
  //   ※アプリが書き込む場合は area_id, sheet_id も付与する
  //
  // uid が住所とその履歴を紐付けるキー
  // ──────────────────────────────────────────────

  /// AREA_DATA_NIGHT のフィールド名規則を自動検出して返す
  /// camelCase (areaId/sheetId) → snake_case (area_id/sheet_id) の順で試す
  static Future<(String, String)> _detectNightFieldNames() async {
    try {
      final snap = await _db
          .collection('AREA_DATA_NIGHT')
          .limit(1)
          .get(const GetOptions(source: Source.server));
      if (snap.docs.isNotEmpty) {
        final fields = snap.docs.first.data().keys.toSet();
        final areaField = fields.contains('areaId') ? 'areaId' : 'area_id';
        final sheetField = fields.contains('sheetId') ? 'sheetId' : 'sheet_id';
        debugPrint('AREA_DATA_NIGHT fields: area=$areaField, sheet=$sheetField, sample=${snap.docs.first.data()}');
        return (areaField, sheetField);
      }
    } catch (e) {
      debugPrint('_detectNightFieldNames error: $e');
    }
    return ('areaId', 'sheetId');
  }

  /// area_id/areaId の値を int として取得するヘルパー
  static int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// 区域番号 → 夜間カード一覧（AREA_DATA_NIGHT から sheetId をユニーク取得）
  static Future<List<Map<String, dynamic>>> getNightCardsForTerritory(
      String territoryNumber) async {
    final areaId = int.tryParse(territoryNumber);
    if (areaId == null) return [];

    final (areaField, sheetField) = await _detectNightFieldNames();

    // int 値でクエリ、ヒットしなければ string 値でも試す
    QuerySnapshot<Map<String, dynamic>> snap;
    snap = await _db
        .collection('AREA_DATA_NIGHT')
        .where(areaField, isEqualTo: areaId)
        .get();

    if (snap.docs.isEmpty) {
      debugPrint('getNightCards: int query empty, retrying with string "$areaId"');
      snap = await _db
          .collection('AREA_DATA_NIGHT')
          .where(areaField, isEqualTo: areaId.toString())
          .get();
    }

    debugPrint('getNightCards: areaId=$areaId, field=$areaField → ${snap.docs.length} docs');

    final sheetIds = <int>{};
    for (final doc in snap.docs) {
      final sid = _toInt(doc.data()[sheetField]);
      if (sid != null) sheetIds.add(sid);
    }

    final cards = sheetIds
        .map((sid) => {'id': '$areaId-$sid', 'areaId': areaId, 'sheetId': sid})
        .toList();
    cards.sort((a, b) => (a['sheetId'] as int).compareTo(b['sheetId'] as int));
    return cards;
  }

  /// 夜間カード: AREA_DATA_NIGHT（住所）＋ AREA_DATA_NIGHT_HISTORY（履歴）を結合して返す
  ///
  /// 返却する各要素のキー:
  ///   id          = uid  （ステータス更新の addressId として使用）
  ///   addressNumber = room_num  （部屋番号 / 表示用番号列）
  ///   townName    = build_name  （棟名 / セクション見出し）
  ///   targetName  = house_name  （居住者名）
  ///   note        = address_check（フル住所）
  ///   rj          = reject フラグ
  ///   visits      = 履歴リスト（start_date 降順）
  static Future<List<Map<String, dynamic>>> getNightCardDataWithHistory(
    String cardName, {
    int historyCount = 5,
  }) async {
    final parsed = _parseCardName(cardName);
    if (parsed == null) return [];

    // 1. 住所マスタ取得（AREA_DATA_NIGHT）— フィールド名を自動検出
    final (areaField, sheetField) = await _detectNightFieldNames();

    QuerySnapshot<Map<String, dynamic>> addrSnap;
    addrSnap = await _db
        .collection('AREA_DATA_NIGHT')
        .where(areaField, isEqualTo: parsed.areaId)
        .where(sheetField, isEqualTo: parsed.sheetId)
        .get();

    if (addrSnap.docs.isEmpty) {
      // string 型でリトライ
      addrSnap = await _db
          .collection('AREA_DATA_NIGHT')
          .where(areaField, isEqualTo: parsed.areaId.toString())
          .where(sheetField, isEqualTo: parsed.sheetId.toString())
          .get();
    }

    debugPrint('getNightCardData: card=$cardName → ${addrSnap.docs.length} addr docs');
    if (addrSnap.docs.isEmpty) return [];

    // 2. uid リストを収集
    final uidToAddr = <String, Map<String, dynamic>>{};
    for (final doc in addrSnap.docs) {
      final data = doc.data();
      final uid = data['uid'] as String? ?? doc.id;
      if (uid.isNotEmpty) uidToAddr[uid] = data;
    }

    // 3. 履歴取得（whereIn は 30 件制限のためバッチ処理）
    final histByUid = <String, List<Map<String, dynamic>>>{};
    final uids = uidToAddr.keys.toList();
    for (int i = 0; i < uids.length; i += 30) {
      final batch = uids.sublist(i, (i + 30).clamp(0, uids.length));
      final histSnap = await _db
          .collection('AREA_DATA_NIGHT_HISTORY')
          .where('uid', whereIn: batch)
          .get();
      for (final doc in histSnap.docs) {
        final data = {'docId': doc.id, ...doc.data()};
        final uid = data['uid'] as String? ?? '';
        if (uid.isNotEmpty) {
          histByUid.putIfAbsent(uid, () => []).add(data);
        }
      }
    }

    // 4. 結合してリストを組み立て
    final results = <Map<String, dynamic>>[];
    for (final entry in uidToAddr.entries) {
      final uid = entry.key;
      final addr = entry.value;
      // フィールド名は camelCase / snake_case 両対応
      final buildName = (addr['buildName'] ?? addr['build_name']) as String? ?? '';
      final roomNum = (addr['roomNum'] ?? addr['room_num'])?.toString() ?? '';
      final houseName = (addr['houseName'] ?? addr['house_name']) as String? ?? '';

      String _toDateStr(dynamic v) {
        if (v == null) return '';
        if (v is String) return v;
        if (v is Timestamp) {
          // タイムゾーンによるずれを防ぐため、一度 UTC にしてから
          // 日本時間 (JST) である +9時間を加算して日付を取得する
          final dt = v.toDate().add(const Duration(hours: 9));
          return '${dt.year}/${dt.month}/${dt.day}';
        }
        if (v is DateTime) {
          return '${v.year}/${v.month}/${v.day}';
        }
        return v.toString();
      }

      final histDocs = histByUid[uid] ?? [];
      histDocs.sort((a, b) {
        final aStr = _toDateStr(a['startDate'] ?? a['start_date']);
        final bStr = _toDateStr(b['startDate'] ?? b['start_date']);
        final aDate = _parseDate(aStr);
        final bDate = _parseDate(bStr);
        if (aDate != null && bDate != null) return bDate.compareTo(aDate);
        return bStr.compareTo(aStr);
      });

      // AREA_DATA_NIGHT_HISTORY のフィールドも camelCase / snake_case 両対応
      final visits = histDocs
          .where((d) {
            final sd = _toDateStr(d['startDate'] ?? d['start_date']);
            final ed = _toDateStr(d['endDate'] ?? d['end_date']);
            return sd.isNotEmpty && ed.isNotEmpty;
          })
          .take(historyCount)
          .map((d) {
            final sd = _toDateStr(d['startDate'] ?? d['start_date']);
            final ed = _toDateStr(d['endDate'] ?? d['end_date']);
            final result = (d['visitResult'] ?? d['visit_result']) as String? ?? '';
            final staff = (d['staffName'] ?? d['staff_name']) as String? ?? '';
            return {
              'id': '${sd}_$ed',
              'startDate': sd,
              'endDate': ed,
              'staffName': staff, // 担当者氏名を取得
              'statusResult': result,
            };
          })
          .toList();

      results.add({
        'id': uid,
        'addressNumber': roomNum,
        'townName': buildName,
        'targetName': houseName,
        'note': (addr['addressCheck'] ?? addr['address_check']) as String? ?? '',
        'rj': addr['reject'] as String? ?? '',
        'visits': visits,
      });
    }

    // build_name → room_num の順でソート
    results.sort((a, b) {
      final aTown = a['townName'] as String? ?? '';
      final bTown = b['townName'] as String? ?? '';
      if (aTown != bTown) return aTown.compareTo(bTown);
      final aNum = a['addressNumber'] as String? ?? '';
      final bNum = b['addressNumber'] as String? ?? '';
      final an = int.tryParse(aNum);
      final bn = int.tryParse(bNum);
      if (an != null && bn != null) return an.compareTo(bn);
      return aNum.compareTo(bNum);
    });

    return results;
  }

  /// AREA_DATA_NORMAL のフィールド名検出（areaId/area_id, sheetId/sheet_id）
  static Future<(String, String)> _detectNormalFieldNames() async {
    try {
      final snap = await _db
          .collection('AREA_DATA_NORMAL')
          .limit(1)
          .get(const GetOptions(source: Source.server));
      if (snap.docs.isNotEmpty) {
        final fields = snap.docs.first.data().keys.toSet();
        final areaField = fields.contains('areaId') ? 'areaId' : 'area_id';
        final sheetField = fields.contains('sheetId') ? 'sheetId' : 'sheet_id';
        debugPrint('AREA_DATA_NORMAL fields: area=$areaField, sheet=$sheetField, sample=${snap.docs.first.data()}');
        return (areaField, sheetField);
      }
    } catch (e) {
      debugPrint('_detectNormalFieldNames error: $e');
    }
    return ('areaId', 'sheetId');
  }

  /// 通常カードのデータ＋履歴を取得（AREA_DATA_NORMAL / AREA_DATA_NORMAL_HISTORY）
  static Future<List<Map<String, dynamic>>> getNormalCardDataWithHistory(
    String cardName, {
    int historyCount = 5,
  }) async {
    final parsed = _parseCardName(cardName);
    if (parsed == null) return [];

    final (areaField, sheetField) = await _detectNormalFieldNames();

    QuerySnapshot<Map<String, dynamic>> addrSnap;
    addrSnap = await _db
        .collection('AREA_DATA_NORMAL')
        .where(areaField, isEqualTo: parsed.areaId)
        .where(sheetField, isEqualTo: parsed.sheetId)
        .get();

    if (addrSnap.docs.isEmpty) {
      addrSnap = await _db
          .collection('AREA_DATA_NORMAL')
          .where(areaField, isEqualTo: parsed.areaId.toString())
          .where(sheetField, isEqualTo: parsed.sheetId.toString())
          .get();
    }

    debugPrint('getNormalCardData: card=$cardName → ${addrSnap.docs.length} addr docs');
    if (addrSnap.docs.isEmpty) return [];

    final uidToAddr = <String, Map<String, dynamic>>{};
    for (final doc in addrSnap.docs) {
      final data = doc.data();
      final uid = data['uid'] as String? ?? doc.id;
      if (uid.isNotEmpty) uidToAddr[uid] = data;
    }

    final histByUid = <String, List<Map<String, dynamic>>>{};
    final uids = uidToAddr.keys.toList();
    debugPrint('getNormalCardData[$cardName]: uids=${uids.length} sample=${uids.take(3).toList()}');
    int totalHist = 0;
    for (int i = 0; i < uids.length; i += 30) {
      final batch = uids.sublist(i, (i + 30).clamp(0, uids.length));
      final histSnap = await _db
          .collection('AREA_DATA_NORMAL_HISTORY')
          .where('uid', whereIn: batch)
          .get();
      totalHist += histSnap.docs.length;
      for (final doc in histSnap.docs) {
        final data = {'docId': doc.id, ...doc.data()};
        final uid = data['uid'] as String? ?? '';
        if (uid.isNotEmpty) histByUid.putIfAbsent(uid, () => []).add(data);
      }
    }
    debugPrint('getNormalCardData[$cardName]: history docs fetched=$totalHist, matched uids=${histByUid.length}');
    if (histByUid.isNotEmpty) {
      final sampleUid = histByUid.keys.first;
      debugPrint('getNormalCardData[$cardName]: sample history for uid=$sampleUid → ${histByUid[sampleUid]!.first}');
    }

    final results = <Map<String, dynamic>>[];
    for (final entry in uidToAddr.entries) {
      final uid = entry.key;
      final addr = entry.value;
      // AREA_DATA_NORMAL の実フィールド: addressNumber(int)=house_num, townName, houseName, addressCheck, rj
      debugPrint('DEBUG addr keys: ${addr.keys.toList()} | house_num=${addr['house_num']} | addressNumber=${addr['addressNumber']}');
      final townName = (addr['townName'] ?? addr['town_name']) as String? ?? '';
      final houseNum =
          (addr['addressNumber'] ?? addr['house_num'] ?? addr['houseNum'])?.toString() ?? '';
      final roomNum = (addr['roomNum'] ?? addr['room_num'])?.toString() ?? '';
      // roomNum に値があれば「house_num-room_num」、無ければ house_num のみ
      final addressNumber =
          roomNum.isNotEmpty ? '$houseNum-$roomNum' : houseNum;
      final houseName = (addr['houseName'] ?? addr['house_name']) as String? ?? '';
      final addressCheck =
          (addr['addressCheck'] ?? addr['address_check']) as String? ?? '';
      final reject = (addr['rj'] ?? addr['reject']) as String? ?? '';
      final houseType = (addr['houseType'] ?? addr['house_type']) as String? ?? '';
      final buildName = (addr['buildName'] ?? addr['build_name']) as String? ?? '';
      final chome = addr['chome']?.toString() ?? '';
      final gaiku = (addr['gaiku'] ?? addr['block'])?.toString() ?? '';
      final ido = (addr['build_ido'] ?? addr['ido'])?.toString() ?? '';
      final keido = (addr['buildKeido'] ?? addr['keido'])?.toString() ?? '';
      String mapLink = '';
      if (ido.isNotEmpty && keido.isNotEmpty) {
        final lat = double.tryParse(ido);
        final lng = double.tryParse(keido);
        if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
          mapLink = 'geo:$ido,$keido';
        }
      }

      String _toDateStr(dynamic v) {
        if (v == null) return '';
        if (v is String) return v;
        if (v is Timestamp) {
          // タイムゾーンによるずれを防ぐため、一度 UTC にしてから
          // 日本時間 (JST) である +9時間を加算して日付を取得する
          final dt = v.toDate().add(const Duration(hours: 9));
          return '${dt.year}/${dt.month}/${dt.day}';
        }
        if (v is DateTime) {
          return '${v.year}/${v.month}/${v.day}';
        }
        return v.toString();
      }

      final histDocs = histByUid[uid] ?? [];
      histDocs.sort((a, b) {
        final aStr = _toDateStr(a['startDate'] ?? a['start_date']);
        final bStr = _toDateStr(b['startDate'] ?? b['start_date']);
        final aDate = _parseDate(aStr);
        final bDate = _parseDate(bStr);
        if (aDate != null && bDate != null) return bDate.compareTo(aDate);
        return bStr.compareTo(aStr);
      });

      final visits = histDocs
          .where((d) {
            final sd = _toDateStr(d['startDate'] ?? d['start_date']);
            final ed = _toDateStr(d['endDate'] ?? d['end_date']);
            return sd.isNotEmpty && ed.isNotEmpty;
          })
          .take(historyCount)
          .map((d) {
            final sd = _toDateStr(d['startDate'] ?? d['start_date']);
            final ed = _toDateStr(d['endDate'] ?? d['end_date']);
            final result = (d['visitResult'] ?? d['visit_result']) as String? ?? '';
            final staff = (d['staffName'] ?? d['staff_name']) as String? ?? '';
            return {
              'id': '${sd}_$ed',
              'startDate': sd,
              'endDate': ed,
              'staffName': staff, // 担当者氏名を取得
              'statusResult': result,
            };
          })
          .toList();

      results.add({
        'id': uid,
        'addressNumber': addressNumber,
        'townName': townName,
        'targetName': houseName,
        'note': addressCheck,
        'rj': reject,
        'visits': visits,
        'houseType': houseType,
        'buildName': buildName,
        'roomNum': roomNum,
        'chome': chome,
        'gaiku': gaiku,
        'mapLink': mapLink,
      });
    }

    results.sort((a, b) {
      final aTown = a['townName'] as String? ?? '';
      final bTown = b['townName'] as String? ?? '';
      if (aTown != bTown) return aTown.compareTo(bTown);
      final an = int.tryParse(a['addressNumber'] as String? ?? '');
      final bn = int.tryParse(b['addressNumber'] as String? ?? '');
      if (an != null && bn != null) return an.compareTo(bn);
      return (a['addressNumber'] as String? ?? '').compareTo(b['addressNumber'] as String? ?? '');
    });

    return results;
  }

  /// 通常カードの訪問ステータスを更新（AREA_DATA_NORMAL_HISTORY に書き込み）
  static Future<void> updateNormalVisitStatus({
    required String cardName,
    required String addressId,
    required String startDate,
    required String endDate,
    required String staffName,
    required String statusResult,
  }) async {
    final parsed = _parseCardName(cardName);
    if (parsed == null) return;

    final safeDateStr = (String s) => s.replaceAll('/', '');
    final docId = '${addressId}_${safeDateStr(startDate)}_${safeDateStr(endDate)}';

    // "yyyy/M/d" → Timestamp（既存ドキュメントが Timestamp 型のためる）
    Timestamp? _toTimestamp(String s) {
      final parts = s.split('/');
      if (parts.length != 3) return null;
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y == null || m == null || d == null) return null;
      return Timestamp.fromDate(DateTime(y, m, d));
    }

    final startTs = _toTimestamp(startDate);
    final endTs = _toTimestamp(endDate);

    await _db.collection('AREA_DATA_NORMAL_HISTORY').doc(docId).set({
      'uid': addressId,
      'type': 'NORMAL',
      'areaId': parsed.areaId,
      'sheetId': parsed.sheetId,
      'startDate': startTs,
      'endDate': endTs,
      'staffName': staffName, // 担当者氏名を追加
      'visitResult': statusResult,
      'timestamp': FieldValue.serverTimestamp(),
    });

    debugPrint('updateNormalVisitStatus: $cardName uid=$addressId status=$statusResult');
  }

  /// 通常カードの変更をリアルタイムで監視
  static Stream<List<Map<String, dynamic>>> watchNormalAddresses(String cardName) {
    final parsed = _parseCardName(cardName);
    if (parsed == null) return Stream.value([]);

    return _db
        .collection('AREA_DATA_NORMAL_HISTORY')
        .where('areaId', isEqualTo: parsed.areaId)
        .where('sheetId', isEqualTo: parsed.sheetId)
        .snapshots()
        .asyncMap((_) => getNormalCardDataWithHistory(cardName));
  }

  /// 夜間カードの訪問ステータスを更新（AREA_DATA_NIGHT_HISTORY に書き込み）
  ///
  /// addressId = uid（AREA_DATA_NIGHT の uid フィールド値）
  /// ドキュメントID = uid_YYYYMMDD_YYYYMMDD 形式で重複防止
  static Future<void> updateNightVisitStatus({
    required String cardName,
    required String addressId, // = uid
    required String startDate,
    required String endDate,
    required String staffName,
    required String statusResult,
  }) async {
    final parsed = _parseCardName(cardName);
    if (parsed == null) return;

    final safeDateStr = (String s) => s.replaceAll('/', '');
    final docId =
        '${addressId}_${safeDateStr(startDate)}_${safeDateStr(endDate)}';

    await _db.collection('AREA_DATA_NIGHT_HISTORY').doc(docId).set({
      'uid': addressId,
      'type': 'NIGHT',
      'area_id': parsed.areaId,
      'sheet_id': parsed.sheetId,
      'start_date': startDate,
      'end_date': endDate,
      'staff_name': staffName, // 担当者氏名を追加
      'visit_result': statusResult,
      'timestamp': FieldValue.serverTimestamp(),
    });

    debugPrint(
        'updateNightVisitStatus: $cardName uid=$addressId status=$statusResult');
  }

  /// オートロックカードの訪問ステータスを更新（AREA_DATA_AUTOLOCK_HISTORY に書き込み）
  static Future<void> updateAutolockVisitStatus({
    required String cardName,
    required String addressId, // = uid
    required String startDate,
    required String endDate,
    required String staffName,
    required String statusResult,
  }) async {
    final parsed = _parseCardName(cardName);
    if (parsed == null) return;

    final safeDateStr = (String s) => s.replaceAll('/', '');
    final docId = '${addressId}_${safeDateStr(startDate)}_${safeDateStr(endDate)}';

    await _db.collection('AREA_DATA_AUTOLOCK_HISTORY').doc(docId).set({
      'uid': addressId,
      'type': 'AUTOLOCK',
      'areaId': parsed.areaId,
      'buildNum': parsed.sheetId,
      'startDate': startDate,
      'endDate': endDate,
      'staffName': staffName,
      'visitResult': statusResult,
      'timestamp': FieldValue.serverTimestamp(),
    });

    debugPrint('updateAutolockVisitStatus: $cardName uid=$addressId status=$statusResult');
  }

  /// 直近 [window] 以内に [cardName] に記録した自分以外のスタッフ一覧を返す
  static Future<List<Map<String, dynamic>>> getRecentAutolockEditors(
    String cardName, {
    Duration window = const Duration(minutes: 10),
    String? excludeStaff,
  }) async {
    final parsed = _parseCardName(cardName);
    if (parsed == null) return [];

    // timestamp の複合インデックスが不要なよう Dart 側でフィルタ
    // buildNum は int/string 両対応でフォールバック
    QuerySnapshot<Map<String, dynamic>> snap;
    snap = await _db
        .collection('AREA_DATA_AUTOLOCK_HISTORY')
        .where('areaId', isEqualTo: parsed.areaId)
        .where('buildNum', isEqualTo: parsed.sheetId)
        .get();

    if (snap.docs.isEmpty) {
      snap = await _db
          .collection('AREA_DATA_AUTOLOCK_HISTORY')
          .where('areaId', isEqualTo: parsed.areaId.toString())
          .where('buildNum', isEqualTo: parsed.sheetId.toString())
          .get();
    }

    final since = DateTime.now().subtract(window);
    return snap.docs
        .map((d) => d.data())
        .where((d) {
          final staff = d['staffName'] as String? ?? '';
          if (staff.isEmpty || staff == excludeStaff) return false;
          final ts = d['timestamp'];
          if (ts == null) return false;
          final dt = ts is Timestamp ? ts.toDate() : null;
          return dt != null && dt.isAfter(since);
        })
        .toList();
  }

  /// 夜間カードの変更をリアルタイムで監視
  /// アプリが書き込んだレコードには area_id / sheet_id が付与されるため、
  /// それを使って AREA_DATA_NIGHT_HISTORY を監視する。
  static Stream<List<Map<String, dynamic>>> watchNightAddresses(
      String cardName) {
    final parsed = _parseCardName(cardName);
    if (parsed == null) return Stream.value([]);

    return _db
        .collection('AREA_DATA_NIGHT_HISTORY')
        .where('area_id', isEqualTo: parsed.areaId)
        .where('sheet_id', isEqualTo: parsed.sheetId)
        .snapshots()
        .asyncMap((_) => getNightCardDataWithHistory(cardName));
  }

  // ──────────────────────────────────────────────
  // ユーティリティ
  // ──────────────────────────────────────────────

  static String _normCardName(String name) {
    return name.trim().replaceAll(RegExp(r'[−–ー\uff70\u2010—―]'), '-');
  }

  // ──────────────────────────────────────────────
  // VISIT_STATUS_OPTIONS
  // ──────────────────────────────────────────────

  /// 訪問ステータス選択肢を VISIT_STATUS_OPTIONS から取得
  /// フィールド: label, color (hex文字列), order, enabled
  static Future<List<Map<String, dynamic>>> getVisitStatusOptions() async {
    final snap = await _db
        .collection('VISIT_STATUS_OPTIONS')
        .get();

    final items = snap.docs.map((d) {
      final data = d.data();
      final colorRaw = data['color'];
      String colorHex = '';
      if (colorRaw is String) {
        colorHex = colorRaw.replaceAll('#', '');
      } else if (colorRaw is Map) {
        colorHex = (colorRaw['hex']?.toString() ?? '').replaceAll('#', '');
      }
      return <String, dynamic>{
        'label': data['label']?.toString() ?? '',
        'color': colorHex,
        'order': (data['order'] as num?)?.toInt() ?? 0,
        'enabled': data['enabled'],
      };
    }).where((m) => m['enabled'] == true && (m['label'] as String).isNotEmpty).toList();
    items.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
    return items;
  }

  // ──────────────────────────────────────────────
  // PUBLIC_WITNESSING / PUBLIC_WITNESSING_OPTIONS
  // 公共エリア証言の申込み
  // ──────────────────────────────────────────────

  /// 選択可能な募集項目を PUBLIC_WITNESSING_OPTIONS から取得
  /// 各ドキュメントのフィールド: day, dayofweek, starttime, endtime, place, (order?)
  static Future<List<Map<String, dynamic>>> getFieldServiceForWeek(DateTime weekStart) async {
    try {
      String fmt(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final startStr = fmt(weekStart);
      final endStr = fmt(weekStart.add(const Duration(days: 6)));
      final snap = await _db
          .collection('FIELD_SERVICE')
          .where('date', isGreaterThanOrEqualTo: startStr)
          .where('date', isLessThanOrEqualTo: endStr)
          .get(const GetOptions(source: Source.server));
      final rows = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      rows.sort((a, b) {
        final da = (a['date'] ?? '').toString();
        final db = (b['date'] ?? '').toString();
        if (da != db) return da.compareTo(db);
        final sa = (a['sortOrder'] as num?)?.toInt() ?? 0;
        final sb = (b['sortOrder'] as num?)?.toInt() ?? 0;
        return sa.compareTo(sb);
      });
      return rows;
    } catch (e) {
      debugPrint('getFieldServiceForWeek error: $e');
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getPublicWitnessingOptions() async {
    try {
      final snap = await _db
          .collection('PUBLIC_WITNESSING_OPTIONS')
          .get(const GetOptions(source: Source.server));
      final items = snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .toList();

      int _dayKey(String day) {
        final m = RegExp(r'(\d+)月(\d+)日').firstMatch(day);
        if (m != null) {
          return int.parse(m.group(1)!) * 100 + int.parse(m.group(2)!);
        }
        return 0;
      }

      items.sort((a, b) {
        final oa = (a['order'] as num?)?.toInt();
        final ob = (b['order'] as num?)?.toInt();
        if (oa != null && ob != null) return oa.compareTo(ob);
        final da = _dayKey(a['day']?.toString() ?? '');
        final db = _dayKey(b['day']?.toString() ?? '');
        if (da != db) return da.compareTo(db);
        final sa = a['starttime']?.toString() ?? '';
        final sb = b['starttime']?.toString() ?? '';
        return sa.compareTo(sb);
      });
      return items;
    } catch (e) {
      debugPrint('getPublicWitnessingOptions error: $e');
      return [];
    }
  }

  /// 申込みを PUBLIC_WITNESSING に保存
  static Future<bool> submitPublicWitnessing({
    required String name,
    required String day,
    required String dayofweek,
    required String starttime,
    required String endtime,
    required String place,
    required String role,
  }) async {
    try {
      await _db.collection('PUBLIC_WITNESSING').add({
        'name': name,
        'day': day,
        'dayofweek': dayofweek,
        'starttime': starttime,
        'endtime': endtime,
        'place': place,
        'role': role,
        'timestamp': Timestamp.now(),
      });
      return true;
    } catch (e) {
      debugPrint('submitPublicWitnessing error: $e');
      return false;
    }
  }

  /// 指定ユーザーの申込み履歴を取得
  static Future<List<Map<String, dynamic>>> getPublicWitnessingForUser(String name) async {
    try {
      final snap = await _db
          .collection('PUBLIC_WITNESSING')
          .where('name', isEqualTo: name)
          .get(const GetOptions(source: Source.server));
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      debugPrint('getPublicWitnessingForUser error: $e');
      return [];
    }
  }

  /// 全ユーザーの申込み履歴を取得
  static Future<List<Map<String, dynamic>>> getAllPublicWitnessing() async {
    try {
      final snap = await _db
          .collection('PUBLIC_WITNESSING')
          .get(const GetOptions(source: Source.server));
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      debugPrint('getAllPublicWitnessing error: $e');
      return [];
    }
  }

  /// 公共エリア証言の割当てを保存
  static Future<bool> savePublicWitnessingAssignment(String slotKey, Map<String, dynamic> data) async {
    try {
      await _db.collection('PUBLIC_WITNESSING_ASSIGNMENTS').doc(slotKey).set({
        ...data,
        'timestamp': Timestamp.now(),
      });
      return true;
    } catch (e) {
      debugPrint('savePublicWitnessingAssignment error: $e');
      return false;
    }
  }

  /// 公共エリア証言の割当てを全取得
  static Future<List<Map<String, dynamic>>> getAllPublicWitnessingAssignments() async {
    try {
      final snap = await _db.collection('PUBLIC_WITNESSING_ASSIGNMENTS').get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      debugPrint('getAllPublicWitnessingAssignments error: $e');
      return [];
    }
  }

  // ──────────────────────────────────────────────
  // PREACHING_REPORT コレクション（奉仕報告）
  // ──────────────────────────────────────────────

  /// 奉仕報告を保存
  static Future<bool> submitPreachingReport({
    required String name,
    required String furigana,
    required String groupName,
    required String gender,
    required int month,
    required String role,
    String? participation,
    int? hours,
    required int bibleStudy,
    required String remarks,
  }) async {
    try {
      await _db.collection('PREACHING_REPORT').add({
        'name': name,
        'furigana': furigana,
        'groupName': groupName,
        'gender': gender,
        'month': month,
        'role': role,
        'participation': participation,
        'hours': hours,
        'bibleStudy': bibleStudy,
        'remarks': remarks,
        'timestamp': Timestamp.now(),
      });
      return true;
    } catch (e) {
      debugPrint('submitPreachingReport error: $e');
      return false;
    }
  }

  // ──────────────────────────────────────────────
  // AREA_INFO_REQUESTS（区域情報登録）
  // ──────────────────────────────────────────────

  /// 新規物件情報を登録
  static Future<bool> submitAreaInfo({
    required String name,
    required String address,
    required String buildingName,
    required String rejectReason,
    required String memo,
  }) async {
    try {
      await _db.collection('AREA_INFO_REQUESTS').add({
        'name': name,
        'address': address,
        'buildingName': buildingName,
        'rejectReason': rejectReason,
        'memo': memo,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
      });
      debugPrint('submitAreaInfo: success');
      return true;
    } catch (e) {
      debugPrint('submitAreaInfo error: $e');
      return false;
    }
  }

  // ──────────────────────────────────────────────
  // ADMIN_NOTIFICATIONS（管理者通知）
  // ──────────────────────────────────────────────

  /// 管理者向け通知を保存
  static Future<void> notifyAdmin({
    required String type,
    required String message,
    required String fromUser,
    Map<String, dynamic>? extra,
  }) async {
    try {
      await _db.collection('ADMIN_NOTIFICATIONS').add({
        'type': type,
        'message': message,
        'fromUser': fromUser,
        'extra': extra ?? {},
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });
      debugPrint('notifyAdmin: $type / $message');
    } catch (e) {
      debugPrint('notifyAdmin error: $e');
    }
  }

  /// 指定ユーザーの奉仕報告履歴を取得
  static Future<List<Map<String, dynamic>>> getPreachingReportsForUser(String name) async {
    try {
      final snap = await _db
          .collection('PREACHING_REPORT')
          .where('name', isEqualTo: name)
          .get(const GetOptions(source: Source.server));
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      debugPrint('getPreachingReportsForUser error: $e');
      return [];
    }
  }

  // ──────────────────────────────────────────────
  // USER_SETTINGS コレクション（ユーザー個別設定）
  // ──────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getUserSettings(String email) async {
    try {
      final doc = await _db
          .collection('USER_SETTINGS')
          .doc(email.toLowerCase())
          .get(const GetOptions(source: Source.server));
      if (doc.exists) return doc.data();
      return null;
    } catch (_) {
      try {
        final doc = await _db
            .collection('USER_SETTINGS')
            .doc(email.toLowerCase())
            .get(const GetOptions(source: Source.cache));
        if (doc.exists) return doc.data();
      } catch (_) {}
      return null;
    }
  }

  static Future<void> saveUserSettings({
    required String email,
    required String primaryColor,
    required String accentColor,
    required String textColor,
    required String logoColor,
    required String logoColorOnDark,
  }) async {
    await _db.collection('USER_SETTINGS').doc(email.toLowerCase()).set({
      'mail': email.toLowerCase(),
      'primaryColor': primaryColor,
      'accentColor': accentColor,
      'textColor': textColor,
      'logoColor': logoColor,
      'logoColorOnDark': logoColorOnDark,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
