import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show max, min;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class DownloadTask {
  final String path;
  final String assetsUrl;
  final String saveDirectory;

  DownloadTask({required this.path, required this.assetsUrl, required this.saveDirectory});
}

class GamedataDownloader {
  /// to save json when parsed correctly
  static dynamic remoteHotUpdateJson;

  /// Converts the file path to the nomenclature used by the server (e.g., gamedata/excel/a.ab -> gamedata_excel_a.dat)
  /// Logic adapted from asset_path_to_server_filename in bundle.py
  static String encodePath(String input) {
    if (input == "hot_update_list.json") return input;

    return input
        .replaceAll(RegExp(r'/'), '_')
        .replaceAll(RegExp(r'#'), '__')
        .replaceAll(RegExp(r'\..*'), '.dat');
  }

  static List<String> getOutdatedHashes(
    Map<String, dynamic> remoteList,
    Map<String, dynamic>? localList,
  ) {
    Map<String, String> localHashes = {};
    if (localList != null) {
      for (var info in localList["abInfos"]) {
        localHashes[info["name"]] = info["hash"];
      }
    }

    List<String> outdated = [];
    for (var info in remoteList["abInfos"]) {
      // We check if the 'meta' key exists in the JSON,
      // or if the word 'gamedata' is in the file name.
      bool isGamedata = info['name'].toString().contains('gamedata');
      bool isMeta = info['meta'] != null;

      if (isGamedata || isMeta) {
        if (localList == null || localHashes[info["name"]] != info["hash"]) {
          outdated.add(info["name"]);
        }
      }
    }
    return outdated;
  }

  /// Function that will run inside each Isolate to download a chunk of files
  static Future<void> _downloadChunkInIsolate(List<DownloadTask> tasks, int isolateId) async {
    final client = http.Client();
    for (var task in tasks) {
      final formattedPath = encodePath(task.path);
      final fileUrl = "${task.assetsUrl}/$formattedPath";

      try {
        final response = await client.get(Uri.parse(fileUrl));
        if (response.statusCode == 200) {
          File(p.join(task.saveDirectory, formattedPath))
            ..createSync(recursive: true)
            ..writeAsBytesSync(response.bodyBytes);
          print('[ISO-$isolateId] Downloaded: ${task.path}');
        } else {
          throw Exception(
            '[ERROR ISO-$isolateId] Failed to download ${task.path}: HTTP ${response.statusCode}',
          );
        }
      } catch (e) {
        throw Exception('[ERROR ISO-$isolateId] Exception downloading ${task.path}: $e');
      }
    }
    client.close();
  }

  /// Main function to orchestrate the update of a server
  static Future<List<String>?> updateServerData({
    required String serverName,
    required String assetsBaseUrl,
    required String saveDirectory,
    required String localDirectory,
    bool forceUpdate = false,
  }) async {
    print('[INFO] Starting update check for server: ${serverName.toUpperCase()}');

    // make sure to null the remote json at the start so dont get mixed with other servers
    remoteHotUpdateJson = null;

    final serverLocalDir = Directory(p.join(localDirectory, serverName));
    final serverSaveDir = Directory(p.join(saveDirectory, serverName));
    if (!serverSaveDir.existsSync()) serverSaveDir.createSync(recursive: true);

    final localHotUpdatePath = File(p.join(serverLocalDir.path, 'hot_update_list.json'));
    Map<String, dynamic>? localHotUpdate;

    if (localHotUpdatePath.existsSync() && !forceUpdate) {
      try {
        localHotUpdate = jsonDecode(localHotUpdatePath.readAsStringSync());
      } catch (e) {
        print('[WARN] Corrupted local hot_update_list.json, forcing full update.');
      }
    }

    // hot_update_list.json
    final remoteHotUpdateUrl = "$assetsBaseUrl/hot_update_list.json";
    final remoteResponse = await http.get(Uri.parse(remoteHotUpdateUrl));

    if (remoteResponse.statusCode != 200) {
      throw Exception('[ERROR] Failed to fetch remote hot_update_list.json');
    }

    final remoteHotUpdate = jsonDecode(remoteResponse.body);
    remoteHotUpdateJson = remoteHotUpdate;
    final filesToDownload = getOutdatedHashes(remoteHotUpdate, localHotUpdate);

    if (filesToDownload.isEmpty) {
      print('[INFO] Server $serverName is already up to date.');
      // We update the local JSON anyway to synchronize minor changes unrelated to gamedata
      localHotUpdatePath.writeAsStringSync(jsonEncode(remoteHotUpdate));
      return null;
    }

    print('[INFO] Found ${filesToDownload.length} updated gamedata bundles for $serverName.');
    return filesToDownload;
  }

  static Future<bool> downloadFilesFromServer({
    required String serverName,
    required List<String> filesToDownload,
    required String assetsBaseUrl,
    required String saveDirectory,
  }) async {
    final serverSaveDir = Directory(p.join(saveDirectory, serverName));

    // Prepare asynchronous download (Task distribution in Isolates)
    final int numOfIso = max(Platform.numberOfProcessors - 1, 1);
    final int chunkSize = (filesToDownload.length / numOfIso).ceil();

    List<List<DownloadTask>> chunks = [];
    for (int i = 0; i < filesToDownload.length; i += chunkSize) {
      final chunkNames = filesToDownload.sublist(i, min(i + chunkSize, filesToDownload.length));
      chunks.add(
        chunkNames
            .map(
              (name) => DownloadTask(
                path: name,
                assetsUrl: assetsBaseUrl,
                saveDirectory: serverSaveDir.path,
              ),
            )
            .toList(),
      );
    }

    print('[INFO] Spawning ${chunks.length} isolates for parallel downloading...');
    List<Future<void>> isolateTasks = [];
    for (int i = 0; i < chunks.length; i++) {
      isolateTasks.add(Isolate.run(() => _downloadChunkInIsolate(chunks[i], i)));
    }

    await Future.wait(isolateTasks);

    print('[OK] Server $serverName download phase completed.');
    return true;
  }

  static void updateHotUpdateJson({required String localDirectory, required String serverName}) {
    final serverLocalDir = Directory(p.join(localDirectory, serverName));
    final localHotUpdatePath = File(p.join(serverLocalDir.path, 'hot_update_list.json'));
    // Save the new hot_update_list locally only when everything is finished
    localHotUpdatePath.writeAsStringSync(jsonEncode(remoteHotUpdateJson));
    print('[INFO] new hot_update_list.json saved for $serverName');
  }
}
