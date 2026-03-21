import 'dart:convert';
import 'package:http/http.dart' as http;

/// Network module for Arknights.
/// Inspired by the logic in arkprts (https://github.com/ashleney/arkprts).
class ArknightsNetwork {
  static const Map<String, String> _configUrls = {
    'en': 'https://ak-conf.arknights.global/config/prod/official/network_config',
    'jp': 'https://ak-conf.arknights.jp/config/prod/official/network_config',
    'kr': 'https://ak-conf.arknights.kr/config/prod/official/network_config',
    'cn': 'https://ak-conf.hypergryph.com/config/prod/official/network_config',
    // 'bili': 'https://ak-conf.hypergryph.com/config/prod/b/network_config',
    'tw': 'https://ak-conf-tw.gryphline.com/config/prod/official/network_config',
  };

  /// Obtains the base URL of the assets and the current resVersion for a specific server.
  static Future<Map<String, String>?> fetchAssetBaseUrl(
    String server, {
    bool failfast = false,
  }) async {
    final configUrl = _configUrls[server];
    if (configUrl == null) {
      print('[ERROR] unknown server: $server');
      return null;
    }

    print('[INFO] Requesting network_config for server $server...');

    try {
      final configResponse = await http.get(Uri.parse(configUrl));

      if (configResponse.statusCode != 200) {
        print('[ERROR] network_config failed for $server (HTTP ${configResponse.statusCode})');
        return null;
      }

      final configData = jsonDecode(configResponse.body);

      // The response packages another JSON in string format inside the 'content' key
      String contentStr = configData['content'];
      Map<String, dynamic> contentObj = jsonDecode(contentStr);

      // Obtain the dynamic key of the current version (e.g., "V011" or whatever the server decides)
      final funcVer = contentObj['funcVer'];
      final networkConfigs = contentObj['configs'][funcVer]['network'];

      // 'hv' contains the version template (e.g., https://.../{0}/version)
      final hvTemplate = networkConfigs['hv'] as String;

      // We replace {0} with the desired platform
      final versionUrl = hvTemplate.replaceAll('{0}', 'Android');

      // Request the exact version file
      final versionResponse = await http.get(Uri.parse(versionUrl));

      if (versionResponse.statusCode != 200) {
        print('[ERROR] Version request failed for $server (HTTP ${versionResponse.statusCode})');
        return null;
      }

      final versionData = jsonDecode(versionResponse.body);
      final resVersion = versionData['resVersion'];

      print('[OK] resVersion resolved for $server: $resVersion');

      // Final assembly of the assets URL
      final huDomain = networkConfigs['hu'];
      final finalAssetUrl = "$huDomain/Android/assets/$resVersion";

      return {'resVersion': resVersion, 'assetsUrl': finalAssetUrl};
    } catch (e) {
      print('[ERROR] Exception in fetchAssetBaseUrl ($server): $e');
      return null;
    }
  }
}
