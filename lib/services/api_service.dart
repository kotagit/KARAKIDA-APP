import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

/// GAS Web API ととの通信を管理するサービス
class ApiService {
  /// 汎用的なリクエスト送信メソッド (リダイレクト対応)
  static Future<http.Response> _sendRequest(String method, dynamic body) async {
    Uri url = Uri.parse(AppConfig.gasApiUrl);
    final client = http.Client();
    http.Response response;
    int redirectCount = 0;
    const int maxRedirects = 5;

    try {
      while (true) {
        final request = http.Request(redirectCount == 0 ? method : 'GET', url)
          ..headers.addAll({
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          })
          ..followRedirects = false;

        if (redirectCount == 0 && body != null) {
          request.body = jsonEncode(body);
        }

        final streamedResponse = await client.send(request).timeout(const Duration(seconds: 30));
        response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 302 || response.statusCode == 301 || response.statusCode == 307 || response.statusCode == 308) {
          if (redirectCount >= maxRedirects) throw Exception('Too many redirects');
          final location = response.headers['location'];
          if (location == null) throw Exception('Redirect location not found');
          url = Uri.parse(location);
          redirectCount++;
          continue;
        }
        break;
      }
      return response;
    } finally {
      client.close();
    }
  }

  /// 許可されている場合は情報を返し、拒否またはエラーの場合は null を返します。
  static Future<Map<String, dynamic>?> checkEmailAllowed(String email) async {
    try {
      print('ApiService: Checking email: $email');
      final response = await _sendRequest('POST', {'email': email.trim()});
      
      if (response.statusCode != 200) {
        print('ApiService: Error response ${response.statusCode}');
        return null;
      }

      if (response.body.isEmpty) {
        print('ApiService: Empty response body');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      print('ApiService: Received data: $data');
      
      if (data['allowed'] == true) {
        return data;
      } else {
        print('ApiService: User not allowed');
        return null;
      }
    } catch (e) {
      print('ApiService: Network Error: $e');
      return null;
    }
  }

  /// 申込み情報を送信する
  static Future<bool> submitApplication(Map<String, dynamic> applicationData, {String? spreadsheetId}) async {
    try {
      final response = await _sendRequest('POST', {
        'action': 'submitApplication',
        'data': applicationData,
        if (spreadsheetId != null) 'spreadsheetId': spreadsheetId,
      });
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('Submit Error: $e');
      return false;
    }
  }

  /// 奉仕報告を送信する
  static Future<bool> submitServiceReport(List<dynamic> row, {String? spreadsheetId}) async {
    try {
      final body = {
        'action': 'submitServiceReport',
        'data': {'row': row},
        'rows': [row],
        'sheetName': 'data', // 奉仕報告のシート名が "data" であることを明示
        if (spreadsheetId != null) 'spreadsheetId': spreadsheetId,
      };
      print('ApiService: Sending service report request: ${jsonEncode(body)}');
      final response = await _sendRequest('POST', body);
      print('ApiService: Response status: ${response.statusCode}');
      print('ApiService: Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('Service Report Error: $e');
      return false;
    }
  }

  /// 区域割当てを保存する (data3 への追記)
  static Future<bool> saveAssignments(List<List<dynamic>> rows, {String? spreadsheetId}) async {
    try {
      final response = await _sendRequest('POST', {
        'action': 'saveAssignments',
        'rows': rows,
        if (spreadsheetId != null) 'spreadsheetId': spreadsheetId,
      });
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        if (data['success'] == true) return true;
        throw Exception(data['error'] ?? 'GAS 側で保存に失敗しました');
      }
      throw Exception('通信エラー (${response.statusCode}): ${response.body}');
    } catch (e) {
      print('Save Assignments Error: $e');
      rethrow;
    }
  }

  /// data3 シートをクリアする
  static Future<bool> clearAssignments({String? spreadsheetId}) async {
    try {
      final response = await _sendRequest('POST', {
        'action': 'clearAssignments',
        if (spreadsheetId != null) 'spreadsheetId': spreadsheetId,
      });
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('Clear Assignments Error: $e');
      return false;
    }
  }

  /// シート名とGIDのマップを取得する
  static Future<Map<String, int>> getSheetIds(String spreadsheetId) async {
    try {
      final response = await _sendRequest('POST', {
        'action': 'getSheetIds',
        'spreadsheetId': spreadsheetId,
      });
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return Map<String, int>.from(data['sheetIds']);
        }
      }
      return {};
    } catch (e) {
      print('GetSheetIds Error: $e');
      return {};
    }
  }

  /// データを読み取る (GAS 経由)
  static Future<List<List<dynamic>>> readRange(String sheetName, {String? spreadsheetId}) async {
    try {
      final response = await _sendRequest('POST', {
        'action': 'readRange',
        'sheetName': sheetName,
        if (spreadsheetId != null) 'spreadsheetId': spreadsheetId,
      });
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return List<List<dynamic>>.from(data['data'].map((row) => List<dynamic>.from(row)));
      }
      throw Exception(data['error'] ?? '読み込み失敗');
    } catch (e) {
      print('Read Error: $e');
      return <List<dynamic>>[];
    }
  }
}
