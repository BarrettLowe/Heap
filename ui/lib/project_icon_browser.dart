import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'heap_style.dart';
import 'mdi_catalog.dart';

Future<String?> showProjectIconBrowser(
  BuildContext context,
  String? selected,
) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  builder: (context) {
    // Android and narrow web use the whole viewport; wide web caps at 640.
    final fullScreen =
        (!kIsWeb && Theme.of(context).platform == TargetPlatform.android) ||
        MediaQuery.sizeOf(context).width < 600;
    final browser = _IconBrowser(selected: selected);
    if (fullScreen) return Dialog.fullscreen(child: browser);
    return Dialog(
      constraints: BoxConstraints(
        maxWidth: 640,
        maxHeight: MediaQuery.sizeOf(context).height - 48,
      ),
      clipBehavior: Clip.antiAlias,
      child: browser,
    );
  },
);

class _IconBrowser extends StatefulWidget {
  const _IconBrowser({required this.selected});
  final String? selected;
  @override
  State<_IconBrowser> createState() => _IconBrowserState();
}

class _IconBrowserState extends State<_IconBrowser> {
  final _search = TextEditingController.fromValue(
    const TextEditingValue(selection: TextSelection.collapsed(offset: 0)),
  );
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();
  final _tileFocus = <String, FocusNode>{};
  List<String> _names = searchMdiIcons('');
  int _columns = 1;
  double _tileHeight = 0;
  double? _labelWidth;
  TextScaler? _scaler;
  TextStyle? _labelStyle;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    for (final node in _tileFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _filter(String query) {
    setState(() => _names = searchMdiIcons(query));
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _focusTile(int index) async {
    if (_names.isEmpty) return;
    if (!_scroll.hasClients) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _names.isEmpty || !_scroll.hasClients) return;
    }
    index = index.clamp(0, _names.length - 1);
    final name = _names[index];
    // Scroll a lazy row into view before requesting its focus.
    final offset = (index ~/ _columns) * (_tileHeight + 8);
    final position = _scroll.position;
    if (offset < position.pixels ||
        offset + _tileHeight > position.pixels + position.viewportDimension) {
      _scroll.jumpTo(offset.clamp(0, position.maxScrollExtent));
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted || !_names.contains(name)) return;
    _node(name).requestFocus();
  }

  FocusNode _node(String name) => _tileFocus.putIfAbsent(
    name,
    () => FocusNode(
      debugLabel: name,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final index = _names.indexOf(name);
        final delta = switch (event.logicalKey) {
          LogicalKeyboardKey.arrowLeft => -1,
          LogicalKeyboardKey.arrowRight => 1,
          LogicalKeyboardKey.arrowUp => -_columns,
          LogicalKeyboardKey.arrowDown => _columns,
          _ => 0,
        };
        if (delta != 0) {
          _focusTile(index + delta);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) {
          Navigator.pop(context, name);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    ),
  );

  double _height(double width, TextScaler scaler, TextStyle style) {
    if (_labelWidth == width && _scaler == scaler && _labelStyle == style) {
      return _tileHeight;
    }
    _labelWidth = width;
    _scaler = scaler;
    _labelStyle = style;
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: scaler,
    );
    var labelHeight = 0.0;
    // Measure the release once per layout, so even its longest name can wrap.
    for (final name in mdiIcons.keys) {
      painter.text = TextSpan(text: mdiLabel(name), style: style);
      painter.layout(maxWidth: width);
      labelHeight = math.max(labelHeight, painter.height);
    }
    painter.dispose();
    // Glyph 28, gap 8, vertical padding 24; every target is at least 48.
    return _tileHeight = math.max(48, labelHeight + 28 + 8 + 24);
  }

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('icon-modal'),
    color: heapCanvas,
    child: Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.pop(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SafeArea(
        child: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const title = Text(
                      'Choose icon',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: heapTitle,
                      ),
                    );
                    final largeText =
                        MediaQuery.textScalerOf(context).scale(1) >= 1.5;
                    final back = IconButton(
                      tooltip: 'Back',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                    );
                    final cancel = TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    );
                    if (largeText) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [back, const Spacer(), cancel]),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: title,
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        back,
                        const Expanded(child: title),
                        cancel,
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Focus(
                  onKeyEvent: (_, event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      _focusTile(0);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (MediaQuery.textScalerOf(context).scale(1) >= 1.5) ...[
                        const ExcludeSemantics(
                          child: Text('Search icons by name'),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Semantics(
                        label: MediaQuery.textScalerOf(context).scale(1) >= 1.5
                            ? 'Search icons by name'
                            : null,
                        child: TextField(
                          key: const Key('icon-search'),
                          controller: _search,
                          focusNode: _searchFocus,
                          autofocus: true,
                          keyboardType: TextInputType.text,
                          selectAllOnFocus: false,
                          decoration: InputDecoration(
                            labelText:
                                MediaQuery.textScalerOf(context).scale(1) >= 1.5
                                ? null
                                : 'Search icons by name',
                            filled: true,
                            fillColor: Colors.white,
                            border: const OutlineInputBorder(),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear',
                                    onPressed: () {
                                      _search.clear();
                                      _filter('');
                                      _searchFocus.requestFocus();
                                    },
                                    icon: const Icon(Icons.clear),
                                  ),
                          ),
                          onChanged: _filter,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _names.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Semantics(
                            liveRegion: true,
                            child: const Text('No icons match your search.'),
                          ),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final scaler = MediaQuery.textScalerOf(context);
                          // Give scaled names roughly 140 logical pixels per column.
                          _columns = math.max(
                            1,
                            ((constraints.maxWidth - 32) / scaler.scale(140))
                                .floor(),
                          );
                          final width =
                              (constraints.maxWidth - 32 - (_columns - 1) * 8) /
                              _columns;
                          final style = Theme.of(context).textTheme.bodyMedium!;
                          final height = _height(width - 24, scaler, style);
                          return Scrollbar(
                            controller: _scroll,
                            child: GridView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: _columns,
                                    mainAxisExtent: height,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                  ),
                              itemCount: _names.length,
                              itemBuilder: (context, index) {
                                final name = _names[index];
                                return _IconTile(
                                  key: ValueKey('mdi-$name'),
                                  name: name,
                                  style: style,
                                  selected: widget.selected == name,
                                  focusNode: _node(name),
                                  onSelected: () =>
                                      Navigator.pop(context, name),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _IconTile extends StatefulWidget {
  const _IconTile({
    super.key,
    required this.name,
    required this.style,
    required this.selected,
    required this.focusNode,
    required this.onSelected,
  });
  final String name;
  final TextStyle style;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onSelected;
  @override
  State<_IconTile> createState() => _IconTileState();
}

class _IconTileState extends State<_IconTile> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: widget.selected,
    label: mdiLabel(widget.name),
    excludeSemantics: true,
    onTap: widget.onSelected,
    child: Material(
      color: widget.selected || _focused ? heapHighlight : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: _focused
            ? const BorderSide(color: heapGreen, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        focusNode: widget.focusNode,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onTap: widget.onSelected,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    mdiIcons[widget.name],
                    size: 28,
                    color: heapInk,
                    applyTextScaling: false,
                  ),
                  if (widget.selected) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.check,
                      size: 20,
                      color: heapGreen,
                      applyTextScaling: false,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                mdiLabel(widget.name),
                textAlign: TextAlign.center,
                style: widget.style.copyWith(color: heapInk),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
