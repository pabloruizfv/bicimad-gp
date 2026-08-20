import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../diagnostics/bicimad_diagnostics.dart';

class HttpResponseData {
  const HttpResponseData({
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

abstract interface class HttpTransport {
  Future<HttpResponseData> get(
    Uri uri, {
    required Map<String, String> headers,
    Duration timeout,
  });

  Future<HttpResponseData> post(
    Uri uri, {
    required Map<String, String> headers,
    required Object body,
    Duration timeout,
  });

  void close();
}

typedef HttpClientFactory = http.Client Function();

class PackageHttpTransport implements HttpTransport {
  PackageHttpTransport({http.Client? client, HttpClientFactory? clientFactory})
    : _client = client ?? (clientFactory ?? createPlatformHttpClient)();

  final http.Client _client;

  @override
  Future<HttpResponseData> get(
    Uri uri, {
    required Map<String, String> headers,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final response = await _client.get(uri, headers: headers).timeout(timeout);
    return HttpResponseData(
      statusCode: response.statusCode,
      body: response.body,
      headers: response.headers,
    );
  }

  @override
  Future<HttpResponseData> post(
    Uri uri, {
    required Map<String, String> headers,
    required Object body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final response = await _client
        .post(uri, headers: headers, body: body)
        .timeout(timeout);
    return HttpResponseData(
      statusCode: response.statusCode,
      body: response.body,
      headers: response.headers,
    );
  }

  @override
  void close() {
    _client.close();
  }
}

@visibleForTesting
http.Client createPlatformHttpClient({
  bool? isAndroid,
  HttpClientFactory? cronetClientFactory,
  HttpClientFactory? ioClientFactory,
}) {
  if (isAndroid ?? Platform.isAndroid) {
    BicimadDiagnostics.log('http_transport', 'created', {
      'implementation': 'cronet',
    });
    return (cronetClientFactory ?? createCronetHttpClient)();
  }

  BicimadDiagnostics.log('http_transport', 'created', {
    'implementation': 'io_client',
  });
  return (ioClientFactory ?? createIoHttpClient)();
}

@visibleForTesting
http.Client createCronetHttpClient() {
  final engine = CronetEngine.build(cacheMode: CacheMode.disabled);
  return CronetClient.fromCronetEngine(engine, closeEngine: true);
}

@visibleForTesting
http.Client createIoHttpClient({HttpClient? httpClient}) {
  return IOClient(httpClient ?? HttpClient());
}
