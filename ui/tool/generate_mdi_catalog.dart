import 'dart:io';

void main() {
  final source = File('tool/mdi-7.4.47.scss').readAsStringSync();
  final matches = RegExp(
    r'"([a-z0-9-]+)": ([0-9A-F]+)',
  ).allMatches(source).toList()..sort((a, b) => a[1]!.compareTo(b[1]!));
  final output = StringBuffer()
    ..writeln(
      '// Generated from @mdi/font 7.4.47. See assets/fonts/PROVENANCE.md.',
    )
    ..writeln('// Regenerate with: dart run tool/generate_mdi_catalog.dart')
    ..writeln("import 'package:flutter/widgets.dart';")
    ..writeln()
    ..writeln('const mdiIcons = <String, IconData>{');
  for (final match in matches) {
    output.writeln(
      "  '${match[1]}': IconData(0x${match[2]!.toLowerCase()}, fontFamily: 'HeapProjectIcons'),",
    );
  }
  output.writeln('};');
  File('lib/mdi_glyphs.dart').writeAsStringSync(output.toString());
  final formatted = Process.runSync('dart', ['format', 'lib/mdi_glyphs.dart']);
  if (formatted.exitCode != 0) {
    stderr.write(formatted.stderr);
    exit(formatted.exitCode);
  }
}
