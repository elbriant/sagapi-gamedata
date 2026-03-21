import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'crypto.dart';

String _getFlatcExecutable() {
  return p.join(Directory.current.path, 'flatc_bin', Platform.isWindows ? 'flatc.exe' : 'flatc');
}

class GamedataDecoder {
  /// Processes a .bytes file by routing it to the correct decoder based on its path and filename,
  /// mirroring the logic found in the Python bundle extraction script.
  static Future<bool> processFile(
    File file,
    String fbsSchemasDir, {
    bool verbose = false,
    bool failfast = false,
  }) async {
    final fileName = p.basename(file.path);
    final rawBytes = file.readAsBytesSync();

    try {
      // Lua Scripts (AES Encrypted)
      if (fileName.endsWith('.lua.bytes')) {
        final decryptedBytes = ArknightsCrypto.decryptCrypticA(rawBytes);
        final cleanName = fileName.replaceAll('.lua.bytes', '.lua');
        _saveRawFile(file, cleanName, decryptedBytes);
        return true;
      }

      // Levels / Activities
      if (file.path.contains(p.join('levels', 'obt')) ||
          file.path.contains(p.join('levels', 'activities'))) {
        // Attempt 1: BSON (skipping 128-byte RSA signature)
        try {
          dynamic decoded = ArknightsCrypto.parseJsonOrBson(rawBytes.sublist(128));
          _saveCleanJson(file, _collapseDicts(decoded));
          return true;
        } catch (_) {}

        // Attempt 2: Flatbuffer using prts___levels fbs
        bool isFbs = await _decodeFlatbuffer(file, rawBytes, 'prts___levels', fbsSchemasDir);
        if (isFbs) return true;

        // Attempt 3: AES decrypt
        try {
          final decryptedAES = ArknightsCrypto.decryptCrypticA(rawBytes);
          dynamic decoded = ArknightsCrypto.parseJsonOrBson(decryptedAES);
          _saveCleanJson(file, _collapseDicts(decoded));
          return true;
        } catch (_) {}

        return false;
      }

      if (fileName == 'buff_template_data.bytes') {
        dynamic decoded = ArknightsCrypto.parseJsonOrBson(rawBytes);
        _saveCleanJson(file, _collapseDicts(decoded));
        return true;
      }

      // Standard Game Tables
      final hexRegex = RegExp(
        r'^(\w+_(?:table|data|const|database|text))(?:[0-9a-fA-F]{6})?\.bytes$',
      );
      final hexMatch = hexRegex.firstMatch(fileName);
      bool fromFbsSchema = false;

      if (hexMatch != null) {
        final schemaName = hexMatch.group(1)!;

        // try FlatBuffers first
        bool isFbsSuccess = await _decodeFlatbuffer(
          file,
          rawBytes,
          schemaName,
          fbsSchemasDir,
          verbose: verbose,
        );

        // If FlatBuffers worked, we finish successfully.
        if (isFbsSuccess) {
          return true;
        } else {
          // If it failed (Segfault, Schema not found, etc.), we do NOT return false.
          // We allow the code to flow to Step 5.
          fromFbsSchema = true;
        }
        // Fallback for unrecognizable files or those that failed the FlatBuffers step
        try {
          final decryptedAES = ArknightsCrypto.decryptCrypticA(rawBytes);
          dynamic decoded = ArknightsCrypto.parseJsonOrBson(decryptedAES);
          _saveCleanJson(file, _collapseDicts(decoded));

          if (fromFbsSchema) {
            print('[INFO] FlatBuffer failed but Cryptic A fallback worked for $fileName');
          }
          return true;
        } catch (e) {
          if (fromFbsSchema) {
            if (failfast) {
              throw Exception(
                '[ERROR] FlatBuffer and Cryptic A fallback also failed for $fileName: $e',
              );
            } else {
              print('[ERROR] FlatBuffer and Cryptic A fallback also failed for $fileName: $e');
            }
          }
        }
      }
    } catch (e) {
      if (failfast) {
        throw Exception('[ERROR] Critical failure processing ${file.path}: $e');
      } else {
        print('[ERROR] Critical failure processing ${file.path}: $e');
      }
      return false;
    }
    if (failfast) {
      throw Exception('[WARN] Unrecognized format or decoding failed for ${file.path}');
    } else {
      print('[WARN] Unrecognized format or decoding failed for ${file.path}');
    }
    return false;
  }

  static Future<bool> _decodeFlatbuffer(
    File originalFile,
    Uint8List rawBytes,
    String schemaName,
    String schemasDir, {
    bool verbose = false,
    bool failfast = false,
  }) async {
    final schemaFile = File(p.join(schemasDir, '$schemaName.fbs'));
    if (!schemaFile.existsSync()) {
      if (verbose) {
        print('[WARN] Schema not found: $schemaName.fbs');
      }
      return false;
    }

    final payloadBytes = rawBytes.length > 128 ? rawBytes.sublist(128) : rawBytes;
    final tempBin = File('${originalFile.path}.tmp.dat');
    tempBin.writeAsBytesSync(payloadBytes);

    final outDir = originalFile.parent.path;
    final args = [
      '--json',
      '--strict-json',
      '--natural-utf8', // ... / ---
      '--defaults-json',
      '--unknown-json', // ... / ---
      '--raw-binary',
      '--no-warnings',
      '--force-empty',
      '-o',
      outDir,
      schemaFile.path,
      '--',
      tempBin.path,
    ];

    final result = await Process.run(_getFlatcExecutable(), args);
    if (tempBin.existsSync()) tempBin.deleteSync();

    if (result.exitCode == 0) {
      final generatedJsonFile = File(
        p.join(outDir, '${p.basenameWithoutExtension(tempBin.path)}.json'),
      );
      if (generatedJsonFile.existsSync()) {
        try {
          String rawJson = generatedJsonFile.readAsStringSync();
          generatedJsonFile.deleteSync();

          rawJson = rawJson.replaceAllMapped(
            RegExp(r'^(\s*)(\d+)(\s*):', multiLine: true),
            (m) => '${m[1]}"${m[2]}"${m[3]}:',
          );
          rawJson = rawJson.replaceAllMapped(
            RegExp(r':\s*(inf|-inf|nan|NaN|Infinity|-Infinity)\s*([,}])'),
            (m) => ': "${m[1]}"${m[2]}',
          );
          rawJson = rawJson.replaceAll(RegExp(r'\\x'), r'\u00');
          rawJson = rawJson.replaceAll(RegExp(r'[\x00-\x1F]'), '');

          dynamic decoded = jsonDecode(rawJson);

          // hydrate nulls
          String fbsContent = schemaFile.readAsStringSync();
          final hydrator = SchemaHydrator(fbsContent);
          decoded = hydrator.hydrate(decoded);

          decoded = _collapseDicts(decoded);

          if (decoded is Map && decoded.length == 1) {
            decoded = decoded.values.first;
          }

          _saveCleanJson(originalFile, decoded);
          return true;
        } catch (e) {
          if (failfast) {
            throw Exception(
              '[ERROR] Failed to parse flatc generated JSON for ${originalFile.path}: $e',
            );
          } else {
            print('[ERROR] Failed to parse flatc generated JSON for ${originalFile.path}: $e');
          }
          return false;
        }
      }
    } else {
      if (verbose) {
        if (result.exitCode == -1073741819 || result.exitCode == 139) {
          if (failfast) {
            throw Exception(
              '[ERROR] flatc Segfault on ${p.basename(originalFile.path)}. The .fbs schema might be outdated.',
            );
          } else {
            print(
              '[ERROR] flatc Segfault on ${p.basename(originalFile.path)}. The .fbs schema might be outdated.',
            );
          }
        } else {
          if (failfast) {
            throw Exception(
              '[ERROR] flatc failed with code ${result.exitCode} for ${originalFile.path}',
            );
          }
          {
            print('[ERROR] flatc failed with code ${result.exitCode} for ${originalFile.path}');
            if (result.stderr.toString().trim().isNotEmpty) {
              print('[FLATC LOG] ${result.stderr.toString().trim()}');
            }
          }
        }
      }
    }
    return false;
  }

  static void _saveRawFile(File originalFile, String newName, Uint8List data) {
    final outPath = p.join(originalFile.parent.path, newName);
    File(outPath).writeAsBytesSync(data);
    if (originalFile.existsSync()) originalFile.deleteSync();
  }

  static void _saveCleanJson(File originalFile, dynamic data) {
    final cleanName = p
        .basenameWithoutExtension(originalFile.path)
        .replaceAll(RegExp(r'[0-9a-fA-F]{6}$'), '');
    final outPath = p.join(originalFile.parent.path, '$cleanName.json');

    var encoder = JsonEncoder.withIndent('  ', (dynamic item) {
      if (item.runtimeType.toString() == 'Int64') return item.toInt();
      return item.toString();
    });

    File(outPath).writeAsStringSync(encoder.convert(data));
    if (originalFile.existsSync()) originalFile.deleteSync();
  }

  /// Recursively collapses Arknights' verbose Key/Value dictionary structures
  /// into standard Dart Maps.
  static dynamic _collapseDicts(dynamic obj) {
    if (obj is List) {
      if (obj.isEmpty) return obj;

      // Check if this list is actually representing a dictionary
      bool isDictPattern = obj.every(
        (elem) =>
            elem is Map &&
            elem.length == 2 &&
            ((elem.containsKey('dict_key') && elem.containsKey('dict_value')) ||
                (elem.containsKey('key') && elem.containsKey('value')) ||
                (elem.containsKey('Key') && elem.containsKey('Value'))),
      );

      if (isDictPattern) {
        Map<String, dynamic> result = {};
        for (var elem in obj) {
          String k = (elem['dict_key'] ?? elem['key'] ?? elem['Key']).toString();
          result[k] = _collapseDicts(elem['dict_value'] ?? elem['value'] ?? elem['Value']);
        }
        return result;
      }
      return obj.map((e) => _collapseDicts(e)).toList();
    } else if (obj is Map) {
      // Handle nested BSON payloads inside JSON
      if (obj.length == 1 && obj.containsKey('jobj_bson')) {
        try {
          final bsonBytes = base64Decode(obj['jobj_bson'].toString());
          final decodedBson = ArknightsCrypto.parseJsonOrBson(bsonBytes);
          return _collapseDicts(decodedBson);
        } catch (_) {}
      }

      Map<String, dynamic> result = {};
      obj.forEach((k, v) => result[k] = _collapseDicts(v));
      return result;
    }
    return obj;
  }
}

class SchemaHydrator {
  final Map<String, Map<String, String>> _tables = {};
  String _rootType = '';

  SchemaHydrator(String fbsContent) {
    // Find the root_type
    final rootMatch = RegExp(r'root_type\s+(\w+);').firstMatch(fbsContent);
    if (rootMatch != null) _rootType = rootMatch.group(1)!;

    // Extract all tables and their variables
    final tableRegex = RegExp(r'table\s+(\w+)\s*\{([^}]+)\}');
    for (final match in tableRegex.allMatches(fbsContent)) {
      final tableName = match.group(1)!;
      final content = match.group(2)!;

      final fields = <String, String>{};
      final fieldRegex = RegExp(r'(\w+)\s*:\s*([^;]+);');
      for (final fMatch in fieldRegex.allMatches(content)) {
        fields[fMatch.group(1)!] = fMatch.group(2)!.trim();
      }
      _tables[tableName] = fields;
    }
  }

  /// Injects nulls and empty lists recursively based on the schema
  dynamic hydrate(dynamic jsonObj, [String? type]) {
    type ??= _rootType;
    if (jsonObj == null) return null;

    if (jsonObj is List) {
      final innerType = type.replaceAll('[', '').replaceAll(']', '');
      return jsonObj.map((e) => hydrate(e, innerType)).toList();
    }

    if (jsonObj is Map) {
      final tableDef = _tables[type];
      if (tableDef == null) return jsonObj; // It's an Enum or other basic structure

      final hydratedMap = <String, dynamic>{};

      // We iterate through the variables that THE SCHEMA says should exist
      tableDef.forEach((fieldName, fieldType) {
        if (jsonObj.containsKey(fieldName)) {
          hydratedMap[fieldName] = hydrate(jsonObj[fieldName], fieldType);
        } else {
          // THE MAGIC: If it doesn't exist, we inject [] for arrays or null for others
          if (fieldType.startsWith('[')) {
            hydratedMap[fieldName] = [];
          } else {
            hydratedMap[fieldName] = null;
          }
        }
      });

      // We preserve any extra keys (like jobj_bson or metadata)
      jsonObj.forEach((k, v) {
        if (!hydratedMap.containsKey(k)) hydratedMap[k] = v;
      });

      return hydratedMap;
    }

    return jsonObj;
  }
}
