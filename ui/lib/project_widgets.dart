import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'heap_style.dart';
import 'mdi_catalog.dart';
import 'project_icon_browser.dart';
import 'project.dart';
import 'project_controller.dart';
import 'task_widgets.dart';

// Fixed 18-degree HSL hue steps (60% saturation, 45% lightness) give 20
// evenly spaced chromatic choices, ordered around the visible hue wheel.
const projectColorValues = <String>[
  '#B82E2E',
  '#B8572E',
  '#B8812E',
  '#B8AA2E',
  '#9CB82E',
  '#73B82E',
  '#49B82E',
  '#2EB83C',
  '#2EB865',
  '#2EB88E',
  '#2EB8B8',
  '#2E8EB8',
  '#2E65B8',
  '#2E3CB8',
  '#492EB8',
  '#732EB8',
  '#9C2EB8',
  '#B82EAA',
  '#B82E81',
  '#B82E57',
];
const projectIcons = <String?, String>{
  null: 'None',
  'folder-outline': 'Folder',
  'home-outline': 'Home',
  'leaf': 'Leaf',
  'wrench-outline': 'Tools',
  'briefcase-outline': 'Work',
};
IconData projectGlyph(String? name) =>
    mdiIcons[name] ?? mdiIcons['folder-outline']!;

class ProjectSwatch extends StatelessWidget {
  const ProjectSwatch(this.value, {super.key, this.size = 12});
  final String? value;
  final double size;
  @override
  Widget build(BuildContext context) {
    final valid =
        value != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value!);
    final color = valid
        ? Color(int.parse(value!.substring(1), radix: 16) | 0xFF000000)
        : null; // Opaque RGB.
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: heapMuted),
      ),
    );
  }
}

class ProjectPicker extends StatefulWidget {
  const ProjectPicker({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.focusNode,
    required this.onChanged,
    this.error,
  });
  final String label;
  final String? value;
  final Map<String?, String> options;
  final FocusNode focusNode;
  final ValueChanged<String?>? onChanged;
  final String? error;
  @override
  State<ProjectPicker> createState() => _ProjectPickerState();
}

class _ProjectPickerState extends State<ProjectPicker> {
  bool _focused = false;
  Map<String?, String> get _options => {
    ...widget.options,
    if (!widget.options.containsKey(widget.value))
      widget.value: widget.label == 'Icon' && mdiIcons.containsKey(widget.value)
          ? mdiLabel(widget.value!)
          : 'Saved ${widget.label.toLowerCase()}: ${widget.value}',
  };
  Future<void> _open() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    if (!mounted) return;
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final entries = _options.entries.toList();
    final selected = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      constraints: BoxConstraints(
        minWidth: box.size.width,
        maxWidth: box.size.width,
      ),
      requestFocus: true,
      items: [
        for (var i = 0; i < entries.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: 48,
            child: Semantics(
              selected: entries[i].key == widget.value,
              child: Container(
                color: entries[i].key == widget.value ? heapHighlight : null,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      projectGlyph(entries[i].key),
                      size: 24,
                      color: heapInk,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(entries[i].value)),
                    const SizedBox(width: 8),
                    if (entries[i].key == widget.value)
                      const Icon(Icons.check, size: 20),
                  ],
                ),
              ),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<int>(
          value: entries.length,
          height: 48,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Browse all…'),
          ),
        ),
      ],
    );
    if (!mounted) return;
    if (selected == entries.length) {
      final icon = await showProjectIconBrowser(context, widget.value);
      if (!mounted) return;
      if (icon != null) widget.onChanged?.call(icon);
    } else if (selected != null) {
      widget.onChanged?.call(entries[selected].key);
    }
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${widget.label}: ${_options[widget.value]}',
    excludeSemantics: true,
    enabled: widget.onChanged != null,
    onTap: widget.onChanged == null ? null : _open,
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        focusNode: widget.focusNode,
        onFocusChange: (value) => setState(() => _focused = value),
        onTap: widget.onChanged == null ? null : _open,
        child: InputDecorator(
          isFocused: _focused,
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
            enabled: widget.onChanged != null,
            errorText: widget.error,
          ),
          child: Row(
            children: [
              Icon(projectGlyph(widget.value), size: 24, color: heapInk),
              const SizedBox(width: 12),
              Expanded(child: Text(_options[widget.value]!)),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      ),
    ),
  );
}

class ProjectColorOption extends StatefulWidget {
  const ProjectColorOption({
    super.key,
    required this.value,
    required this.selected,
    required this.onTap,
    this.nameFocus,
  });
  final String? value;
  final bool selected;
  final VoidCallback? onTap;
  final FocusNode? nameFocus;
  @override
  State<ProjectColorOption> createState() => _ProjectColorOptionState();
}

class _ProjectColorOptionState extends State<ProjectColorOption> {
  final _focus = FocusNode();
  bool _focused = false;
  bool _pointerDown = false;
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNone = widget.value == null;
    final label = isNone ? 'None, cleared' : 'Color ${widget.value}';
    return Semantics(
      key: Key(
        isNone
            ? 'project-color-option-none'
            : 'project-color-option-${widget.value}',
      ),
      label: label,
      button: true,
      enabled: widget.onTap != null,
      selected: widget.selected,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: SizedBox(
        width: isNone ? null : 52,
        height: 52,
        child: Listener(
          onPointerDown: (_) =>
              _pointerDown = widget.nameFocus?.hasFocus ?? false,
          child: InkWell(
            focusNode: _focus,
            onFocusChange: (value) => setState(() => _focused = value),
            borderRadius: BorderRadius.circular(28),
            onTap: widget.onTap == null
                ? null
                : () {
                    widget.onTap!();
                    if (_pointerDown) widget.nameFocus?.requestFocus();
                    _pointerDown = false;
                  },
            child: Center(
              child: isNone
                  ? Container(
                      key: Key(
                        _focused
                            ? 'project-color-focus-none'
                            : 'project-color-none',
                      ),
                      constraints: const BoxConstraints(minHeight: 48),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _focused ? heapGreen : heapMuted,
                          width: _focused ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('None'),
                          if (widget.selected) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.check, size: 16),
                          ],
                        ],
                      ),
                    )
                  : Container(
                      key: Key(
                        _focused
                            ? 'project-color-focus-${widget.value}'
                            : 'project-color-circle-${widget.value}',
                      ),
                      width: 44,
                      height: 44,
                      decoration: _focused
                          ? BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: heapGreen, width: 2),
                            )
                          : null,
                      alignment: Alignment.center,
                      child: Container(
                        key: Key('project-color-swatch-${widget.value}'),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: ProjectSwatchColor.parse(widget.value!),
                          shape: BoxShape.circle,
                          border: Border.all(color: heapMuted),
                        ),
                        alignment: Alignment.center,
                        child: widget.selected
                            ? Container(
                                key: const Key('project-color-selected-badge'),
                                width: 22,
                                height: 22,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  size: 18,
                                  color: heapInk,
                                ),
                              )
                            : null,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class ProjectColorPalette extends StatelessWidget {
  const ProjectColorPalette({
    super.key,
    required this.value,
    required this.onChanged,
    required this.nameFocus,
    this.error,
  });
  final String? value;
  final ValueChanged<String?>? onChanged;
  final FocusNode nameFocus;
  final String? error;
  @override
  Widget build(BuildContext context) {
    final inPalette = projectColorValues.contains(value?.toUpperCase());
    final savedColor = value != null && !inPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Color',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final color in projectColorValues)
              ProjectColorOption(
                value: color,
                selected: value?.toUpperCase() == color,
                nameFocus: nameFocus,
                onTap: onChanged == null ? null : () => onChanged!(color),
              ),
            ProjectColorOption(
              value: null,
              selected: value == null,
              nameFocus: nameFocus,
              onTap: onChanged == null ? null : () => onChanged!(null),
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (savedColor)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              label: 'Saved color: $value',
              excludeSemantics: true,
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  const Text('Current saved color: '),
                  ProjectSwatch(value, size: 20),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class ProjectSwatchColor {
  static Color parse(String value) =>
      Color(int.parse(value.substring(1), radix: 16) | 0xFF000000);
}

class ProjectRow extends StatefulWidget {
  const ProjectRow({
    super.key,
    required this.project,
    required this.onOpen,
    required this.focusNode,
    this.highlighted = false,
  });
  final Project project;
  final VoidCallback onOpen;
  final FocusNode focusNode;
  final bool highlighted;
  @override
  State<ProjectRow> createState() => _ProjectRowState();
}

class _ProjectRowState extends State<ProjectRow> {
  bool _focused = false;
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${widget.project.name}. Edit project.',
    excludeSemantics: true,
    onTap: widget.onOpen,
    child: Material(
      color: _focused || _hovered || widget.highlighted
          ? heapHighlight
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: _focused
            ? const BorderSide(color: heapGreen, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        focusNode: widget.focusNode,
        onTap: widget.onOpen,
        borderRadius: BorderRadius.circular(20),
        onFocusChange: (v) => setState(() => _focused = v),
        onHover: (v) => setState(() => _hovered = v),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: ProjectSwatch(widget.project.color),
              ),
              const SizedBox(width: 12),
              Icon(projectGlyph(widget.project.icon), size: 24, color: heapInk),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.project.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: heapTitle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ProjectsListBody extends StatelessWidget {
  const ProjectsListBody({
    super.key,
    required this.controller,
    required this.scroll,
    required this.headingFocus,
    required this.addFocus,
    required this.onAdd,
    required this.onOpen,
    required this.rowKey,
    required this.rowFocus,
    this.highlightedId,
    this.notice,
  });
  final ProjectsController controller;
  final ScrollController scroll;
  final FocusNode headingFocus;
  final FocusNode addFocus;
  final VoidCallback onAdd;
  final ValueChanged<String> onOpen;
  final GlobalKey Function(String) rowKey;
  final FocusNode Function(String) rowFocus;
  final String? highlightedId;
  final String? notice;
  @override
  Widget build(BuildContext context) => CappedContent(
    child: SingleChildScrollView(
      controller: scroll,
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width >= 600 ? 24 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Focus(
            focusNode: headingFocus,
            child: const Text(
              'Projects',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: heapTitle,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: const Key('add-project'),
              focusNode: addFocus,
              onPressed: onAdd,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 20),
                    SizedBox(width: 8),
                    Flexible(child: Text('Add project')),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (notice != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(liveRegion: true, child: Text(notice!)),
            ),
          if (controller.loading)
            Semantics(
              liveRegion: true,
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  Text('Loading projects…'),
                ],
              ),
            ),
          if (controller.error != null)
            StatusPanel(
              message: controller.loaded
                  ? 'Showing previously loaded projects. This list may be out of date.'
                  : 'Could not load projects.',
              actions: [
                TextButton(
                  onPressed: controller.loading ? null : controller.load,
                  child: const Text('Retry'),
                ),
              ],
            ),
          if (controller.loaded &&
              controller.projects.isEmpty &&
              !controller.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No projects yet.\nUse Add project to create one.',
                style: TextStyle(color: heapMuted),
              ),
            ),
          for (final project in controller.projects)
            Column(
              children: [
                ProjectRow(
                  key: rowKey(project.id),
                  project: project,
                  onOpen: () => onOpen(project.id),
                  focusNode: rowFocus(project.id),
                  highlighted: highlightedId == project.id,
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 72),
                  child: Divider(height: 1, color: heapDivider),
                ),
              ],
            ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}
