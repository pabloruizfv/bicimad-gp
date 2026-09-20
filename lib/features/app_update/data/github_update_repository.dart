import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

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

  final http.Client _client;

  Future<AppUpdateInfo> checkForUpdate() async {
    final package = await PackageInfo.fromPlatform();
    final policyResponse = await _client.get(_policyUri);
    final releaseResponse = await _client.get(
      _releaseUri,
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'bicimad-gp-app',
      },
    );
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
    final assets = release['assets'];
    if (minimum.isEmpty || latest.isEmpty || assets is! List) {
      throw const FormatException('Metadatos de actualización incompletos.');
    }
    final apk = assets
        .whereType<Map>()
        .cast<Map<Object?, Object?>>()
        .firstWhere(
          (asset) =>
              asset['name']?.toString().toLowerCase().endsWith('.apk') ?? false,
          orElse: () => <Object?, Object?>{},
        );
    final apkUrl = Uri.tryParse(apk['browser_download_url']?.toString() ?? '');
    if (apkUrl == null || apkUrl.host != 'github.com') {
      throw const FormatException('APK de actualización no válida.');
    }

    return AppUpdateInfo(
      currentVersion: package.version,
      latestVersion: latest,
      minimumSupportedVersion: minimum,
      apkUrl: apkUrl,
      sha256: _readSha256(policy),
    );
  }

  Future<File> downloadApk(
    AppUpdateInfo info,
    void Function(double progress) onProgress,
  ) async {
    final request = http.Request('GET', info.apkUrl);
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw const HttpException('No se ha podido descargar la actualización.');
    }
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/bicimad-gp-update.apk');
    final sink = file.openWrite();
    final digest = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(digest);
    var received = 0;
    final total = response.contentLength;
    await for (final chunk in response.stream) {
      received += chunk.length;
      input.add(chunk);
      sink.add(chunk);
      onProgress(total == null || total <= 0 ? 0 : received / total);
    }
    input.close();
    await sink.close();
    final expected = info.sha256?.toLowerCase();
    if (expected != null &&
        expected.isNotEmpty &&
        digest.events.single.toString() != expected) {
      await file.delete();
      throw const FormatException('La firma de la descarga no coincide.');
    }
    onProgress(1);
    return file;
  }

  String? _readSha256(Map policy) {
    final value = policy['sha256']?.toString().trim().toLowerCase();
    if (value == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      return null;
    }
    return value;
  }

  void dispose() => _client.close();
}
