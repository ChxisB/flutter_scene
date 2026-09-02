/// The node palette: what can be added to a graph, and how it is found.
///
/// Two ways in, and the second is the one that matters. Opened from the
/// toolbar it lists the whole library. Opened by dragging a wire into empty
/// space it lists only what that pin can reach, beside where the wire was let
/// go — so "what can go here" is answered in place rather than by scrolling a
/// hundred and thirty nodes.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_scene/visual_script.dart';

import '../shell/editor_theme.dart';
import '../shell/panel_chrome.dart';
import 'visual_script_layout.dart';

/// How well [type] matches [needle], or null when it does not match at all.
///
/// Lower is better. A hit on the label beats one on the id beats one in the
/// documentation, and an earlier hit beats a later one — so typing "for"
/// offers For Loop and For Each before Format Text, which is what somebody
/// typing "for" into a graph editor meant.
int? visualScriptPaletteRank(VisualScriptNodeType type, String needle) {
  if (needle.isEmpty) return 0;
  final label = type.label.toLowerCase();
  if (label.startsWith(needle)) return label.length - needle.length;
  final inLabel = label.indexOf(needle);
  if (inLabel >= 0) return 100 + inLabel;
  final inId = type.id.toLowerCase().indexOf(needle);
  if (inId >= 0) return 300 + inId;
  final inDoc = type.doc.toLowerCase().indexOf(needle);
  if (inDoc >= 0) return 600 + inDoc;
  return null;
}

/// The first pin on a fresh node of [type] that a wire carrying [fromType]
/// could land on, or null when there is none.
///
/// Declaration order, so it picks the pin a node leads with — a Branch's exec
/// input, a Print's value — which is nearly always the one meant.
/// [fromIsInput] says which end was dragged: from an input, the new node
/// supplies a value, and from an output it receives one.
String? visualScriptConnectablePin(
  VisualScriptNodeType type,
  VisualScriptType fromType, {
  required bool fromIsInput,
  VisualScriptGraphLookup? graphs,
}) {
  // A node that is not in a graph yet, purely to ask a dynamic-pin type what
  // shape a fresh one would have.
  final probe = VisualScriptNodeSpec(id: -1, type: type.id);
  final candidates = fromIsInput
      ? type.outputsOf(probe, graphs)
      : type.inputsOf(probe, graphs);
  for (final pin in candidates) {
    final ok = fromIsInput
        ? pin.type.connectsTo(fromType)
        : fromType.connectsTo(pin.type);
    if (ok) return pin.id;
  }
  return null;
}

/// The node palette: everything that can be added, searched and grouped.
///
/// Two ways in, and the second is the one that matters. Opened from the
/// toolbar it lists the whole library. Opened by dragging a wire into empty
/// space it lists only what that pin can reach, next to where the wire was
/// let go — so the question "what can go here" is answered in place rather
/// than by scrolling a list of a hundred and thirty nodes.
class VisualScriptPalette extends StatefulWidget {
  const VisualScriptPalette({
    super.key,
    required this.registry,
    required this.onPick,
    required this.onDismiss,
    this.anchor,
    this.accepts,
    this.fromType,
    this.fromIsInput = false,
  });

  final VisualScriptRegistry registry;
  final ValueChanged<VisualScriptNodeType> onPick;
  final VoidCallback onDismiss;

  /// Where to put the panel, in the canvas widget's coordinates. Null puts it
  /// in the top-right corner.
  final Offset? anchor;

  /// Whether a node type has a pin the dragged wire could land on. Null shows
  /// everything.
  final bool Function(VisualScriptNodeType type)? accepts;

  /// What was dragged, for the line above the search box.
  final VisualScriptType? fromType;
  final bool fromIsInput;

  @override
  State<VisualScriptPalette> createState() => _VisualScriptPaletteState();
}

class _VisualScriptPaletteState extends State<VisualScriptPalette> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final needle = _query.trim().toLowerCase();
    final accepts = widget.accepts;
    final ranked = <(int, VisualScriptNodeType)>[];
    for (final type in widget.registry.all) {
      if (accepts != null && !accepts(type)) continue;
      final rank = visualScriptPaletteRank(type, needle);
      if (rank != null) ranked.add((rank, type));
    }
    // Searching ranks across every category; browsing keeps the categories,
    // because a list of a hundred and thirty things needs the headings.
    final searching = needle.isNotEmpty;
    if (searching) ranked.sort((a, b) => a.$1.compareTo(b.$1));
    final matches = [for (final entry in ranked) entry.$2];

    final panel = Container(
      width: 300,
      constraints: const BoxConstraints(maxHeight: 420),
      decoration: editorPanelBox(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.fromType case final dragged?)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.linear_scale,
                    size: 12,
                    color: visualScriptTypeColor(dragged),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      widget.fromIsInput
                          ? 'Nodes that give a ${dragged.label}'
                          : 'Nodes that take a ${dragged.label}',
                      style: editorMicroText,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: _SearchBox(
              onChanged: (value) => setState(() => _query = value),
              onSubmit: () {
                if (matches.isNotEmpty) widget.onPick(matches.first);
              },
            ),
          ),
          if (matches.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              child: Text(
                widget.fromType == null
                    ? 'Nothing matches that.'
                    : 'Nothing here connects to a ${widget.fromType!.label}.',
                style: editorMicroText,
              ),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                children: searching
                    ? [
                        for (final type in matches)
                          _PaletteRow(
                            type: type,
                            onTap: () => widget.onPick(type),
                          ),
                      ]
                    : [
                        for (final category in widget.registry.categories)
                          if (matches.any((t) => t.category == category)) ...[
                            EditorSectionHeader(label: category),
                            for (final type in matches)
                              if (type.category == category)
                                _PaletteRow(
                                  type: type,
                                  onTap: () => widget.onPick(type),
                                ),
                          ],
                      ],
              ),
            ),
        ],
      ),
    );

    return Positioned.fill(
      child: GestureDetector(
        onTap: widget.onDismiss,
        child: ColoredBox(
          // A palette opened at a point is a menu and should not dim the
          // graph behind it; one opened from the toolbar is a mode.
          color: widget.anchor == null
              ? editorSurfaceColor.withValues(alpha: 0.55)
              : const Color(0x00000000),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final anchor = widget.anchor;
              if (anchor == null) {
                return Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: GestureDetector(onTap: () {}, child: panel),
                  ),
                );
              }
              // Kept inside the canvas, so a wire let go near the right edge
              // does not open a menu half off screen.
              final left = anchor.dx
                  .clamp(0.0, math.max(0.0, constraints.maxWidth - 300))
                  .toDouble();
              final top = anchor.dy
                  .clamp(0.0, math.max(0.0, constraints.maxHeight - 200))
                  .toDouble();
              return Stack(
                children: [
                  Positioned(
                    left: left,
                    top: top,
                    child: GestureDetector(onTap: () {}, child: panel),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The palette's search field, focused as it appears.
class _SearchBox extends StatefulWidget {
  const _SearchBox({required this.onChanged, required this.onSubmit});

  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: editorFieldHeight + 4,
    child: EditorFieldSurface(
      hovered: true,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          const Icon(Icons.search, size: 12, color: editorMutedTextColor),
          const SizedBox(width: 5),
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              style: editorBodyText,
              cursorWidth: 1,
              cursorColor: editorAccentColor,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search nodes',
                hintStyle: editorMicroText,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: widget.onChanged,
              // Return takes the best match, so the whole interaction can be
              // drag, type three letters, return.
              onSubmitted: (_) => widget.onSubmit(),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PaletteRow extends StatelessWidget {
  const _PaletteRow({required this.type, required this.onTap});

  final VisualScriptNodeType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(type.label, style: editorBodyText),
          Text(
            type.doc,
            style: editorMicroText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}
