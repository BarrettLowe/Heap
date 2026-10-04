import 'package:heap_app/heap_api.dart';
import 'package:heap_app/project.dart';

const projectId = 'd4be2fc9-49b7-46a6-9981-1f063eed03ea';
Map<String, dynamic> projectJson({
  String id = projectId,
  String name = 'Garden',
}) => {
  'id': id,
  'name': name,
  'description': 'Keep this description',
  'color': '#779252',
  'icon': 'leaf',
  'status': 'active',
  'created_at': '2026-10-03T12:34:56.000000Z',
  'updated_at': '2026-10-03T12:34:56.000000Z',
  'completed_at': null,
};
Project project({String id = projectId, String name = 'Garden'}) =>
    Project.fromJson(projectJson(id: id, name: name));

class FakeProjects implements ProjectService {
  List<Project> items = [project()];
  Future<List<Project>> Function()? onList;
  Future<Project> Function(String)? onGet;
  Future<Project> Function(ProjectDraft, Project?)? onSave;
  Future<void> Function(String)? onDelete;
  int lists = 0, gets = 0, writes = 0, deletes = 0;
  ProjectDraft? lastDraft;
  Project? lastOriginal;
  @override
  Future<List<Project>> listProjects() {
    lists++;
    return onList?.call() ?? Future.value(items);
  }

  @override
  Future<Project> getProject(String id) {
    gets++;
    return onGet?.call(id) ?? Future.value(items.first);
  }

  @override
  Future<Project> saveProject(ProjectDraft draft, {Project? original}) async {
    writes++;
    lastDraft = draft;
    lastOriginal = original;
    final result =
        await (onSave?.call(draft, original) ??
            Future.value(
              Project.fromJson({
                ...projectJson(name: draft.name.trim()),
                'color': draft.color,
                'icon': draft.icon,
                'description': original?.description,
              }),
            ));
    items = [result];
    return result;
  }

  @override
  Future<void> deleteProject(String id) async {
    deletes++;
    await onDelete?.call(id);
  }
}
