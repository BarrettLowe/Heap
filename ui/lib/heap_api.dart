import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'inbox_task.dart';
import 'task_detail.dart';
import 'project.dart';

export 'inbox_task.dart';

const Duration requestTimeout = Duration(seconds: 10);

class HeapApiException implements Exception {
  const HeapApiException(
    this.message, {
    this.unknownOutcome = false,
    this.statusCode,
    this.code,
    this.fieldErrors = const {},
  });

  final String message;
  final bool unknownOutcome;
  final int? statusCode;
  final String? code;
  final Map<String, String> fieldErrors;

  @override
  String toString() => message;
}

abstract interface class InboxService {
  Future<List<InboxTask>> listInbox();
  Future<InboxTask> capture(String title);
}

abstract interface class OrganizationService {
  Future<TaskDetail> getTask(String id);
  Future<List<TaskDetail>> listOnHeap();
  Future<TaskDetail> saveOrganization(OrganizationSubmission submission);
}

abstract interface class ProjectService {
  Future<List<Project>> listProjects();
  Future<Project> getProject(String id);
  Future<Project> saveProject(ProjectDraft draft, {Project? original});
  Future<void> deleteProject(String id);
}

class HeapApi implements InboxService, OrganizationService, ProjectService {
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
      final tasks = (body['items'] as List).map(InboxTask.fromJson).toList();
      if (tasks.map((task) => task.id).toSet().length != tasks.length) {
        throw const FormatException('Duplicate inbox IDs.');
      }
      return List<InboxTask>.unmodifiable(tasks);
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
        if (response.statusCode >= 500 || response.statusCode < 400) {
          throw const HeapApiException(
            'Capture may have succeeded. Refresh the inbox before submitting again.',
            unknownOutcome: true,
          );
        }
        throw HeapApiException(_messageFor(response.statusCode));
      }
      try {
        return InboxTask.fromCaptureJson(jsonDecode(response.body));
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

  @override
  Future<TaskDetail> getTask(String id) async {
    final response = await _organizationRead('/api/v1/tasks/$id');
    try {
      final detail = TaskDetail.fromJson(jsonDecode(response.body));
      if (detail.id != id) throw const FormatException('Wrong task ID.');
      return detail;
    } on FormatException {
      throw const HeapApiException('The server returned an invalid response.');
    }
  }

  @override
  Future<List<TaskDetail>> listOnHeap() async {
    final response = await _organizationRead('/api/v1/heap');
    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || body['items'] is! List) {
        throw const FormatException('Invalid on-the-heap list.');
      }
      final tasks = (body['items'] as List).map(TaskDetail.fromJson).toList();
      if (tasks.any((task) => task.status != 'on_heap') ||
          tasks.map((task) => task.id).toSet().length != tasks.length) {
        throw const FormatException('Invalid on-the-heap items.');
      }
      return List.unmodifiable(tasks);
    } on FormatException {
      throw const HeapApiException('The server returned an invalid response.');
    }
  }

  Future<http.Response> _organizationRead(String path) async {
    try {
      final response = await client.get(baseUri.resolve(path)).timeout(timeout);
      if (response.statusCode != 200) throw _organizationError(response);
      return response;
    } on HeapApiException {
      rethrow;
    } on TimeoutException {
      throw const HeapApiException('The server took too long to respond.');
    } catch (_) {
      throw const HeapApiException('Could not reach the server.');
    }
  }

  @override
  Future<TaskDetail> saveOrganization(OrganizationSubmission submission) async {
    try {
      final response = await client
          .put(
            baseUri.resolve(
              '/api/v1/tasks/${submission.original.id}/organization',
            ),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(submission.toJson()),
          )
          .timeout(timeout);
      if (response.statusCode >= 500 ||
          (response.statusCode < 400 && response.statusCode != 200)) {
        throw _unknownSave;
      }
      if (response.statusCode != 200) throw _organizationError(response);
      final detail = TaskDetail.fromJson(jsonDecode(response.body));
      if (detail.id != submission.original.id || detail.status == 'completed') {
        throw const FormatException('Invalid saved task.');
      }
      return detail;
    } on HeapApiException {
      rethrow;
    } catch (_) {
      throw _unknownSave;
    }
  }

  @override
  Future<List<Project>> listProjects() async {
    final response = await _organizationRead('/api/v1/projects');
    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || body['items'] is! List) {
        throw const FormatException('Invalid projects list.');
      }
      final projects = (body['items'] as List).map(Project.fromJson).toList();
      if (projects.map((project) => project.id).toSet().length !=
          projects.length) {
        throw const FormatException('Duplicate project IDs.');
      }
      return List.unmodifiable(projects);
    } on FormatException {
      throw const HeapApiException('The server returned an invalid response.');
    }
  }

  @override
  Future<Project> getProject(String id) async {
    final response = await _organizationRead('/api/v1/projects/$id');
    try {
      final project = Project.fromJson(jsonDecode(response.body));
      if (project.id != id) throw const FormatException('Wrong project ID.');
      return project;
    } on FormatException {
      throw const HeapApiException('The server returned an invalid response.');
    }
  }

  static const _unknownProjectWrite = HeapApiException(
    'The request may have succeeded. Your draft has been kept. Check projects before trying again.',
    unknownOutcome: true,
  );

  @override
  Future<Project> saveProject(ProjectDraft draft, {Project? original}) async {
    try {
      final uri = baseUri.resolve(
        '/api/v1/projects${original == null ? '' : '/${original.id}'}',
      );
      final headers = const {'content-type': 'application/json'};
      final body = jsonEncode(draft.toJson(description: original?.description));
      final response =
          await (original == null
                  ? client.post(uri, headers: headers, body: body)
                  : client.put(uri, headers: headers, body: body))
              .timeout(timeout);
      final expectedStatus = original == null ? 201 : 200;
      _checkProjectWrite(response, expectedStatus);
      final project = Project.fromJson(jsonDecode(response.body));
      if (original != null && project.id != original.id) {
        throw const FormatException('Wrong saved project ID.');
      }
      return project;
    } on HeapApiException {
      rethrow;
    } catch (_) {
      throw _unknownProjectWrite;
    }
  }

  @override
  Future<void> deleteProject(String id) async {
    try {
      final response = await client
          .delete(baseUri.resolve('/api/v1/projects/$id'))
          .timeout(timeout);
      _checkProjectWrite(response, 200);
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || body['deleted'] != true) {
        throw const FormatException('Invalid deletion response.');
      }
    } on HeapApiException {
      rethrow;
    } catch (_) {
      throw _unknownProjectWrite;
    }
  }

  void _checkProjectWrite(http.Response response, int expectedStatus) {
    if (response.statusCode >= 500 ||
        (response.statusCode < 400 && response.statusCode != expectedStatus)) {
      throw _unknownProjectWrite;
    }
    if (response.statusCode != expectedStatus) {
      throw _organizationError(response);
    }
  }

  static const _unknownSave = HeapApiException(
    'The save may have succeeded. Your draft has been kept. Reload the saved task before trying again.',
    unknownOutcome: true,
  );

  HeapApiException _organizationError(http.Response response) {
    String? code;
    final fields = <String, String>{};
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> &&
          body['error'] is Map<String, dynamic>) {
        final error = body['error'] as Map<String, dynamic>;
        if (error['code'] is String) code = error['code'] as String;
        if (error['fields'] is List) {
          for (final field in error['fields'] as List) {
            if (field is Map<String, dynamic> &&
                {
                  'name',
                  'color',
                  'icon',
                  'title',
                  'priority',
                  'duration_minutes',
                  'externally_blocked',
                }.contains(field['field']) &&
                field['message'] is String) {
              fields[field['field'] as String] = field['message'] as String;
            }
          }
        }
      }
    } on FormatException {
      // HTTP rejection still preserves the draft when the error body is invalid.
    }
    return HeapApiException(
      _messageFor(response.statusCode),
      statusCode: response.statusCode,
      code: code,
      fieldErrors: Map.unmodifiable(fields),
    );
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
