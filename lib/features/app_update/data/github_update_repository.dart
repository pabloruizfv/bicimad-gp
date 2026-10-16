import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../domain/app_update.dart';

class GithubUpdateRepository {
  GithubUpdateRepository({http.Client? client})
    : _client = client ?? http.Client();

  static final _policyUri = Uri.parse(
    'https://raw.githubusercontent.com/pabloruizfv/bicimad-gp/main/update_policy.json',
  );
  static final _releaseUri = Uri.parse(
    'https://api.github.com/repos/pabloruizfv/bicimad-gp/releases/latest',
  );
  static final _defaultReleasePageUri = Uri.parse(
    'https://github.com/pabloruizfv/bicimad-gp/releases/latest',
  );

  final http.Client _client;

  Future<AppUpdateInfo> checkForUpdate() async {
    final package = await PackageInfo.fromPlatform();
    const headers = {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'bicimad-gp-app',
    };
    final responses = await Future.wait([
      _client.get(_policyUri, headers: headers),
      _client.get(_releaseUri, headers: headers),
    ]);
    final policyResponse = responses[0];
    final releaseResponse = responses[1];
    if (policyResponse.statusCode != 200 || releaseResponse.statusCode != 200) {
      throw const HttpException('No se ha podido comprobar la versión.');
    }

    final policy = jsonDecode(policyResponse.body);
    final release = jsonDecode(releaseResponse.body);
    if (policy is! Map || release is! Map) {
      throw const FormatException('Respuesta de actualización no válida.');
    }
    final minimum = policy['minimumSupportedVersion']?.toString().trim() ?? '';
    final tag = release['tag_name']?.toString().trim() ?? '';
    final latest = tag.startsWith('v') ? tag.substring(1) : tag;
    if (minimum.isEmpty || latest.isEmpty) {
      throw const FormatException('Metadatos de actualización incompletos.');
    }
    final releaseUrl = Uri.tryParse(release['html_url']?.toString() ?? '');

    return AppUpdateInfo(
      currentVersion: package.version,
      latestVersion: latest,
      minimumSupportedVersion: minimum,
      releaseUrl: releaseUrl?.host == 'github.com'
          ? releaseUrl!
          : _defaultReleasePageUri,
    );
  }

  void dispose() => _client.close();
}
