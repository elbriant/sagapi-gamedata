import 'dart:io';
import 'package:path/path.dart' as p;

class FbsManager {
  static Future<bool> ensureSchemasAvailable(String targetServer) async {
    final fbsRepoPath = p.join(Directory.current.path, 'fbs_repo');

    if (!Directory(fbsRepoPath).existsSync()) {
      print('[INFO] Downloading FlatBuffers schemas from sagapi-flatbuffers...');
      final result = await Process.run('git', [
        'clone',
        '--branch',
        'fbs',
        '--depth',
        '1',
        'https://github.com/elbriant/sagapi-flatbuffers.git',
        fbsRepoPath,
      ]);

      if (result.exitCode != 0) {
        throw Exception('[ERROR] Error cloning schemas: ${result.stderr}');
      }
    } else {
      await Process.run('git', ['pull'], workingDirectory: fbsRepoPath);
    }

    String schemaServer = resolveSchemaServer(targetServer);
    final schemaPath = p.join(fbsRepoPath, schemaServer);

    if (!Directory(schemaPath).existsSync()) {
      throw Exception('[ERROR] Schema directory not found for $schemaServer');
    }

    print('[OK] Schemas successfully obtained in ./fbs_repo.');
    return true;
  }

  static String resolveSchemaServer(String gameServer) {
    return switch (gameServer) {
      'cn' || 'tw' => gameServer,
      _ => 'global',
    };
  }

  static String getSchemaDirectory(String gameServer) {
    return p.join(Directory.current.path, 'fbs_repo', resolveSchemaServer(gameServer));
  }
}
