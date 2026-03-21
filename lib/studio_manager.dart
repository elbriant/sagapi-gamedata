import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

class StudioManager {
  static Future<bool> ensureStudioInstalled({bool forceUpdate = false}) async {
    final akstudioDir = path.join(Directory.current.path, 'ArknightsStudioCLI');

    if (!Directory(akstudioDir).existsSync() || forceUpdate) {
      print('[INFO] Downloading ArknightsStudioCLI...');
      if (Directory(akstudioDir).existsSync()) {
        Directory(akstudioDir).deleteSync(recursive: true);
      }

      try {
        final response = await http.get(
          Uri.parse(r'https://api.github.com/repos/aelurum/AssetStudio/releases'),
        );
        final data = (jsonDecode(response.body) as List).firstWhere(
          (e) => (e['tag_name'] as String).startsWith('ak'),
        );
        final url = (data['assets'] as List).firstWhere(
          (element) =>
              (element['name'] as String).contains(RegExp(r'net8', caseSensitive: false)) &&
              (element['name'] as String).contains(RegExp(r'portable', caseSensitive: false)),
        )['browser_download_url'];

        final responseDownload = await http.get(Uri.parse(url));

        Directory(akstudioDir).createSync();
        final archive = ZipDecoder().decodeBytes(responseDownload.bodyBytes);

        for (final entry in archive) {
          if (entry.isFile) {
            final fileBytes = entry.readBytes()!;
            File(path.join(akstudioDir, entry.name))
              ..createSync(recursive: true)
              ..writeAsBytesSync(fileBytes);
          }
        }

        if (Platform.isLinux || Platform.isMacOS) {
          await Process.run("chmod", ["+x", path.join(akstudioDir, "ArknightsStudioCLI")]);
        }

        print('[OK] ArknightsStudioCLI installed successfully.');
      } catch (e) {
        throw Exception('[ERROR] Failed to download ArknightsStudioCLI: $e');
      }
    }
    return true;
  }
}
