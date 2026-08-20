import 'dart:collection';

import 'package:bicimad_social/core/network/http_transport.dart';
import 'package:bicimad_social/core/storage/secure_key_value_store.dart';

class InMemorySecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> values = {};
  final List<String> readKeys = [];
  final List<String> writtenKeys = [];
  final List<String> deletedKeys = [];

  @override
  Future<void> delete(String key) async {
    deletedKeys.add(key);
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    readKeys.add(key);
    return values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    writtenKeys.add(key);
    values[key] = value;
  }
}

class QueuedHttpTransport implements HttpTransport {
  QueuedHttpTransport([Iterable<HttpResponseData> responses = const []])
    : _responses = Queue.of(responses);

  final Queue<HttpResponseData> _responses;
  final List<HttpRequestRecord> requests = [];
  bool isClosed = false;

  void addResponse(HttpResponseData response) {
    _responses.add(response);
  }

  @override
  Future<HttpResponseData> get(
    Uri uri, {
    required Map<String, String> headers,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    requests.add(HttpRequestRecord(method: 'GET', uri: uri, headers: headers));
    return _responses.removeFirst();
  }

  @override
  Future<HttpResponseData> post(
    Uri uri, {
    required Map<String, String> headers,
    required Object body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    requests.add(
      HttpRequestRecord(method: 'POST', uri: uri, headers: headers, body: body),
    );
    return _responses.removeFirst();
  }

  @override
  void close() {
    isClosed = true;
  }
}

class HttpRequestRecord {
  const HttpRequestRecord({
    required this.method,
    required this.uri,
    required this.headers,
    this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final Object? body;
}
