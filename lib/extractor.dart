import 'dart:io';
import 'package:path/path.dart' as p;

class GamedataExtractor {
  /// Extracts all TextAsset from the bundles of a server and saves them in a clean directory
  static Future<bool> extractServerBundles(
    String serverName,
    String bundlesDir,
    String outputDir,
  ) async {
    final serverBundlesPath = p.join(bundlesDir, serverName);
    if (!Directory(serverBundlesPath).existsSync()) {
      print('[WARN] No bundles to extract for $serverName.');
      return false;
    }

    final serverOutputPath = p.join(outputDir, serverName);
    if (!Directory(serverOutputPath).existsSync()) {
      Directory(serverOutputPath).createSync(recursive: true);
    }

    print('[INFO] Extracting TextAssets (Gamedata) from $serverName...');

    final cliPath = p.join(Directory.current.path, 'ArknightsStudioCLI', 'ArknightsStudioCLI.dll');

    // We extract only 'TextAsset' type and use the 'container' folder format
    var result = await Process.run("dotnet", [
      cliPath,
      serverBundlesPath,
      "-t",
      "TextAsset",
      "-o",
      serverOutputPath,
      "-g",
      "container",
    ]);

    if (result.exitCode == 0) {
      print('[OK] Extraction completed for $serverName.');
      return true;
    } else {
      throw Exception('[ERROR] ArknightsStudioCLI failed:${result.stderr}');
    }
  }
}
