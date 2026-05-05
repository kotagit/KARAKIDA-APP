import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class DriveFile {
  final String id;
  final String name;
  final String? mimeType;

  DriveFile({required this.id, required this.name, this.mimeType});
}

class DriveService {
  static const String _baseUrl = 'https://www.googleapis.com/drive/v3';

  final Map<String, String> _authHeaders;

  DriveService(this._authHeaders);

  /// Target folder ID on Google Drive (Regular territories)
  static const String targetFolderId = '1j2HXbHkJQYCpOVtRSsqUnHCBUtHm7rue';

  /// Target folder ID for Night territories
  static const String nightFolderId = '1e3CflOlQgSmvhQSGbxuM15PlQOrQNrIM';

  /// Get all spreadsheets once and return a map of normalized names to files for fast lookup
  Future<Map<String, DriveFile>> getAllSpreadsheetsMap() async {
    const query = "mimeType='application/vnd.google-apps.spreadsheet' and trashed=false";
    final encodedQuery = Uri.encodeComponent(query);
    final map = <String, DriveFile>{};
    String? nextPageToken;
    int totalFetched = 0;

    String norm(String s) => s.trim().replaceAll(RegExp(r'[−–ーｰ‐—―]'), '-');

    try {
      do {
        final url = '$_baseUrl/files?q=$encodedQuery&fields=nextPageToken,files(id,name,mimeType)&pageSize=1000&supportsAllDrives=true&includeItemsFromAllDrives=true${nextPageToken != null ? "&pageToken=$nextPageToken" : ""}';
        
        final response = await http.get(Uri.parse(url), headers: _authHeaders);
        if (response.statusCode != 200) {
          throw Exception('Failed to list files: ${response.body}');
        }
        
        final data = json.decode(response.body);
        final files = data['files'] as List;
        nextPageToken = data['nextPageToken'] as String?;
        totalFetched += files.length;
        
        for (final f in files) {
          final driveFile = DriveFile(id: f['id'], name: f['name'], mimeType: f['mimeType']);
          final normalizedName = norm(driveFile.name);
          
          // 同じ名前がある場合は最初に見つかったものを優先（通常は1つのはず）
          if (!map.containsKey(normalizedName)) {
            map[normalizedName] = driveFile;
          }
        }
      } while (nextPageToken != null);

      debugPrint('DriveService: Fetched $totalFetched total spreadsheets, unique normalized: ${map.length}');
      return map;
    } catch (e) {
      debugPrint('DriveService: Error in getAllSpreadsheetsMap: $e');
      return map;
    }
  }

  /// List Google Sheets files in the target folder
  Future<List<DriveFile>> listSheets() async {
    final query = Uri.encodeComponent(
      "'$targetFolderId' in parents and mimeType='application/vnd.google-apps.spreadsheet' and trashed=false",
    );
    final url = '$_baseUrl/files?q=$query&fields=files(id,name,mimeType)&orderBy=name&supportsAllDrives=true&includeItemsFromAllDrives=true';
    final response = await http.get(Uri.parse(url), headers: _authHeaders);
    if (response.statusCode != 200) {
      throw Exception('Failed to list files: ${response.body}');
    }
    final data = json.decode(response.body);
    final files = data['files'] as List;
    return files
        .map((f) => DriveFile(
              id: f['id'],
              name: f['name'],
              mimeType: f['mimeType'],
            ))
        .toList();
  }

  /// Find a folder by name (e.g., "No.1", "No.50") and get file objects inside it
  /// Returns a list of DriveFile objects sorted
  Future<List<DriveFile>> getFilesInFolder(String folderName, {String? parentFolderId}) async {
    try {
      debugPrint('DriveService: Searching for folder "$folderName" (parent: $parentFolderId)');
      
      final cleanSearchName = folderName.replaceAll('★', '').replaceAll('☆', '').trim();
      final namesToTry = [
        folderName, // "15★"
        cleanSearchName, // "15"
        'No.$folderName', // "No.15★"
        'No.$cleanSearchName', // "No.15"
        '$cleanSearchName★', // "15★" (★を再付与)
        '$cleanSearchName☆', // "15☆"
      ].toSet().toList();

      String folderId = '';

      // 1. まずは親フォルダ内を探す（指定がある場合）
      if (parentFolderId != null) {
        String query = "'$parentFolderId' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false";
        final folderQuery = Uri.encodeComponent(query);
        final folderUrl = '$_baseUrl/files?q=$folderQuery&fields=files(id,name)&pageSize=1000&supportsAllDrives=true&includeItemsFromAllDrives=true';
        debugPrint('DriveService: Parent folder query URL: $folderUrl');
        final folderResponse = await http.get(Uri.parse(folderUrl), headers: _authHeaders);
        debugPrint('DriveService: Parent folder response status: ${folderResponse.statusCode}');

        if (folderResponse.statusCode == 200) {
          final folderData = json.decode(folderResponse.body);
          final foldersInParent = folderData['files'] as List;
          debugPrint('DriveService: Found ${foldersInParent.length} subfolders in parent');
          for (final folder in foldersInParent) {
            final name = (folder['name'] as String).trim();
            debugPrint('  Subfolder: "$name"');
          }

          for (final folder in foldersInParent) {
            final name = (folder['name'] as String).toLowerCase().trim();
            if (namesToTry.any((p) => name == p.toLowerCase())) {
              folderId = folder['id'];
              debugPrint('DriveService: Found folder "$name" in parent folder.');
              break;
            }
          }
        } else {
          debugPrint('DriveService: Parent folder search failed: ${folderResponse.body}');
        }
      }

      // 2. 親フォルダ内で見つからない場合は、グローバルに検索する
      if (folderId.isEmpty) {
        debugPrint('DriveService: Not found in parent. Searching globally...');
        for (final name in namesToTry) {
          String query = "name='$name' and mimeType='application/vnd.google-apps.folder' and trashed=false";
          final folderQuery = Uri.encodeComponent(query);
          final folderUrl = '$_baseUrl/files?q=$folderQuery&fields=files(id,name)&pageSize=10&supportsAllDrives=true&includeItemsFromAllDrives=true';
          final folderResponse = await http.get(Uri.parse(folderUrl), headers: _authHeaders);

          if (folderResponse.statusCode == 200) {
            final folderData = json.decode(folderResponse.body);
            final foldersFound = folderData['files'] as List;
            if (foldersFound.isNotEmpty) {
              folderId = foldersFound[0]['id'];
              debugPrint('DriveService: Found folder "$name" globally with ID: $folderId');
              break;
            }
          }
        }
      }

      // 3. 完全一致で見つからない場合、contains検索でフォールバック
      if (folderId.isEmpty) {
        debugPrint('DriveService: Exact match not found. Trying contains search for "$cleanSearchName"...');
        String query = "name contains '$cleanSearchName' and mimeType='application/vnd.google-apps.folder' and trashed=false";
        final folderQuery = Uri.encodeComponent(query);
        final folderUrl = '$_baseUrl/files?q=$folderQuery&fields=files(id,name)&pageSize=20&supportsAllDrives=true&includeItemsFromAllDrives=true';
        final folderResponse = await http.get(Uri.parse(folderUrl), headers: _authHeaders);

        if (folderResponse.statusCode == 200) {
          final folderData = json.decode(folderResponse.body);
          final foldersFound = folderData['files'] as List;
          debugPrint('DriveService: Contains search found ${foldersFound.length} folders');
          for (final folder in foldersFound) {
            final fname = (folder['name'] as String).trim();
            debugPrint('  Candidate: "$fname"');
            // フォルダ名が数字部分で始まるか、数字部分を含むものを採用
            final fnameClean = fname.replaceAll(RegExp(r'[★☆\s]'), '');
            if (fnameClean == cleanSearchName || fname.startsWith(cleanSearchName)) {
              folderId = folder['id'];
              debugPrint('DriveService: Found folder "$fname" via contains search with ID: $folderId');
              break;
            }
          }
        }
      }

      if (folderId.isEmpty) {
        debugPrint('DriveService: No matching folder found for "$folderName".');
        return [];
      }

      // Step 2: Get file objects in this folder (Google Sheets files)
      final filesQuery = Uri.encodeComponent(
        "'$folderId' in parents and mimeType='application/vnd.google-apps.spreadsheet' and trashed=false",
      );
      final filesUrl = '$_baseUrl/files?q=$filesQuery&fields=files(id,name,mimeType)&orderBy=name&supportsAllDrives=true&includeItemsFromAllDrives=true';
      final filesResponse = await http.get(Uri.parse(filesUrl), headers: _authHeaders);

      if (filesResponse.statusCode != 200) {
        return [];
      }

      final filesData = json.decode(filesResponse.body);
      final files = filesData['files'] as List;

      final driveFiles = files
          .map((f) => DriveFile(
                id: f['id'],
                name: (f['name'] as String).trim(),
                mimeType: f['mimeType'],
              ))
          .toList();

      // Sort by numeric value (e.g., "1-5" before "1-10")
      driveFiles.sort((a, b) {
        final aMatch = RegExp(r'(\d+)[−\-](\d+)').firstMatch(a.name);
        final bMatch = RegExp(r'(\d+)[−\-](\d+)').firstMatch(b.name);

        if (aMatch != null && bMatch != null) {
          final aFirst = int.parse(aMatch.group(1)!);
          final aSecond = int.parse(aMatch.group(2)!);
          final bFirst = int.parse(bMatch.group(1)!);
          final bSecond = int.parse(bMatch.group(2)!);

          if (aFirst != bFirst) {
            return aFirst.compareTo(bFirst);
          }
          return aSecond.compareTo(bSecond);
        }
        return a.name.compareTo(b.name);
      });

      return driveFiles;
    } catch (e) {
      return [];
    }
  }
}
