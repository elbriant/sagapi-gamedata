import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

class FlatcManager {
  /// Downloads the latest official version of flatc from Google's repository
  static Future<bool> ensureFlatcInstalled({bool forceUpdate = false}) async {
    final flatcDir = p.join(Directory.current.path, 'flatc_bin');
    final exeName = Platform.isWindows ? 'flatc.exe' : 'flatc';
    final flatcPath = p.join(flatcDir, exeName);

    if (!File(flatcPath).existsSync() || forceUpdate) {
      print('[INFO] Downloading the latest version of flatc...');
      if (Directory(flatcDir).existsSync()) {
        Directory(flatcDir).deleteSync(recursive: true);
      }
      Directory(flatcDir).createSync(recursive: true);

      try {
        final response = await http.get(
          Uri.parse('https://api.github.com/repos/google/flatbuffers/releases/latest'),
        );
        final data = jsonDecode(response.body);
        final assets = data['assets'] as List;

        // Determine the current platform
        String platformKey = 'Linux';
        if (Platform.isWindows) platformKey = 'Windows';
        if (Platform.isMacOS) platformKey = 'Mac';

        // Search for the asset corresponding to the platform
        final asset = assets.firstWhere((element) {
          final name = (element['name'] as String).toLowerCase();
          return name.contains(platformKey.toLowerCase()) &&
              name.contains('flatc') &&
              name.endsWith('.zip');
        }, orElse: () => null);

        if (asset == null) {
          print('[ERROR] No flatc binary found for this platform.');
          return false;
        }

        final downloadUrl = asset['browser_download_url'];
        final downloadRes = await http.get(Uri.parse(downloadUrl));

        // Unzip the zip file in memory and extract only the executable
        final archive = ZipDecoder().decodeBytes(downloadRes.bodyBytes);
        for (final file in archive) {
          if (file.isFile && file.name.contains('flatc')) {
            final fileBytes = file.readBytes()!;
            File(flatcPath).writeAsBytesSync(fileBytes);
            break;
          }
        }

        // Give execution permissions on Unix systems
        if (!Platform.isWindows) {
          await Process.run('chmod', ['+x', flatcPath]);
        }

        print('[OK] flatc installed successfully in $flatcPath.');
      } catch (e) {
        print('[ERROR] Failed to download flatc: $e');
        return false;
      }
    }
    return true;
  }

  /// Returns the absolute path to the flatc executable
  static String getExecutablePath() {
    return p.join(Directory.current.path, 'flatc_bin', Platform.isWindows ? 'flatc.exe' : 'flatc');
  }
}
