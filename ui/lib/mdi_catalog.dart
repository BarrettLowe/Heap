import 'mdi_glyphs.dart';

export 'mdi_glyphs.dart';

String mdiLabel(String name) {
  final words = name.replaceAll('-', ' ');
  return '${words[0].toUpperCase()}${words.substring(1)}';
}

List<String> searchMdiIcons(String query) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'[\s-]+'))
      .where((word) => word.isNotEmpty)
      .toList();
  return mdiIcons.keys.where((name) => words.every(name.contains)).toList();
}
