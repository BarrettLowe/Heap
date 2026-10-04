import 'inbox_task.dart';

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.description,
    required this.color,
    required this.icon,
  });
  final String id;
  final String name;
  final String? description;
  final String? color;
  final String? icon;

  factory Project.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        !value.keys.toSet().containsAll({
          'id',
          'name',
          'description',
          'color',
          'icon',
          'status',
          'created_at',
          'updated_at',
          'completed_at',
        })) {
      throw const FormatException('Project is missing required fields.');
    }
    final id = value['id'];
    final name = value['name'];
    if (id is! String ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty ||
        value['status'] != 'active' ||
        value['completed_at'] != null ||
        value['created_at'] is! String ||
        value['updated_at'] is! String ||
        [
          'description',
          'color',
          'icon',
        ].any((key) => value[key] != null && value[key] is! String)) {
      throw const FormatException('Invalid project fields.');
    }
    InboxTask.parseUtcTimestamp(value['created_at'] as String);
    InboxTask.parseUtcTimestamp(value['updated_at'] as String);
    return Project(
      id: id,
      name: name,
      description: value['description'] as String?,
      color: value['color'] as String?,
      icon: value['icon'] as String?,
    );
  }
}

class ProjectDraft {
  const ProjectDraft({this.name = '', this.color, this.icon});
  factory ProjectDraft.fromProject(Project project) => ProjectDraft(
    name: project.name,
    color: project.color,
    icon: project.icon,
  );
  final String name;
  final String? color;
  final String? icon;
  bool matches(ProjectDraft other) =>
      name == other.name && color == other.color && icon == other.icon;
  Map<String, Object?> toJson({String? description}) => {
    'name': name.trim(),
    'description': description,
    'color': color,
    'icon': icon,
  };
}

class ProjectEditorResult {
  const ProjectEditorResult.saved(this.project, {required this.created})
    : deleted = false;
  const ProjectEditorResult.deleted()
    : project = null,
      created = false,
      deleted = true;
  final Project? project;
  final bool created;
  final bool deleted;
}
