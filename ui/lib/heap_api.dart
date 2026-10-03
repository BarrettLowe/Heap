import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const Duration requestTimeout = Duration(seconds: 10);

class InboxTask {
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  static final RegExp _timestampPattern = RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$',
  );

  const InboxTask({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory InboxTask.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Task must be an object.');
    }
    const fields = <String>{
      'id',
      'title',
      'status',
      'created_at',
      'updated_at',
    };
    if (!value.keys.toSet().containsAll(fields)) {
      throw const FormatException('Task is missing required fields.');
    }
    final id = value['id'];
    final title = value['title'];
    final status = value['status'];
    final createdAt = value['created_at'];
    final updatedAt = value['updated_at'];
    if (id is! String ||
        title is! String ||
        status is! String ||
        createdAt is! String ||
        updatedAt is! String) {
      throw const FormatException('Task fields have invalid types.');
    }
    if (!_uuidPattern.hasMatch(id) ||
        title.trim().isEmpty ||
        status != 'inbox' ||
        !_timestampPattern.hasMatch(createdAt) ||
        !_timestampPattern.hasMatch(updatedAt)) {
      throw const FormatException('Task fields have invalid values.');
    }
    final createdDate = DateTime.parse(createdAt);
    final updatedDate = DateTime.parse(updatedAt);
    if (_utcTimestamp(createdDate) != createdAt ||
        _utcTimestamp(updatedDate) != updatedAt) {
      throw const FormatException('Task timestamps are not valid UTC dates.');
    }
    return InboxTask(
      id: id,
      title: title,
      status: status,
      createdAt: createdDate,
      updatedAt: updatedDate,
    );
  }

  static String _utcTimestamp(DateTime date) {
    final iso = date.toIso8601String();
    // Dart omits the final 3 fractional digits when microseconds are zero.
    return date.microsecond == 0
        ? '${iso.substring(0, iso.length - 1)}000Z'
        : iso;
  }
}

class HeapApiException implements Exception {
  const HeapApiException(this.message, {this.unknownOutcome = false});

  final String message;
  final bool unknownOutcome;

  @override
  String toString() => message;
}

abstract interface class InboxService {
  Future<List<InboxTask>> listInbox();
  Future<InboxTask> capture(String title);
}

class HeapApi implements InboxService {
  HeapApi({
    required this.client,
    required this.baseUri,
    this.timeout = requestTimeout,
  });

  final http.Client client;
  final Uri baseUri;
  final Duration timeout;

  void close() => client.close();

  @override
  Future<List<InboxTask>> listInbox() async {
    try {
      final response = await client
          .get(baseUri.resolve('/api/v1/inbox'))
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw HeapApiException(_messageFor(response.statusCode));
      }
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || body['items'] is! List) {
        throw const FormatException('Invalid inbox response.');
      }
      return List<InboxTask>.unmodifiable(
        (body['items'] as List).map(InboxTask.fromJson),
      );
    } on HeapApiException {
      rethrow;
    } on TimeoutException {
      throw const HeapApiException('The server took too long to respond.');
    } on FormatException {
      throw const HeapApiException('The server returned an invalid response.');
    } catch (_) {
      throw const HeapApiException('Could not reach the server.');
    }
  }

  @override
  Future<InboxTask> capture(String title) async {
    try {
      final response = await client
          .post(
            baseUri.resolve('/api/v1/tasks'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'title': title}),
          )
          .timeout(timeout);
      if (response.statusCode != 201) {
        if (response.statusCode >= 500) {
          throw const HeapApiException(
            'Capture may have succeeded. Refresh the inbox before submitting again.',
            unknownOutcome: true,
          );
        }
        throw HeapApiException(_messageFor(response.statusCode));
      }
      try {
        return InboxTask.fromJson(jsonDecode(response.body));
      } on FormatException {
        throw const HeapApiException(
          'Capture may have succeeded. Refresh the inbox before submitting again.',
          unknownOutcome: true,
        );
      }
    } on HeapApiException {
      rethrow;
    } on TimeoutException {
      throw const HeapApiException(
        'Capture may have succeeded. Refresh the inbox before submitting again.',
        unknownOutcome: true,
      );
    } catch (_) {
      throw const HeapApiException(
        'Capture may have succeeded. Refresh the inbox before submitting again.',
        unknownOutcome: true,
      );
    }
  }

  String _messageFor(int statusCode) => switch (statusCode) {
    404 => 'The server endpoint was not found.',
    415 || 422 => 'The server rejected this request.',
    _ => 'The server returned an unexpected response ($statusCode).',
  };
}

Uri? parseApiBaseUri(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.port > 65535 ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    return null;
  }
  return uri.replace(path: '', query: null, fragment: null);
}
