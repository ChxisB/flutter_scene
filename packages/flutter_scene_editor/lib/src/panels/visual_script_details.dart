/// The details of the thing being edited when it is not a node: the open
/// graph's own signature, or a selected variable.
///
/// A graph's parameters and results are as real as any node's pins — they
/// become the Entry node's outputs and every Call node's inputs — and until
/// now they could only be written in Dart. A signature you cannot declare is
/// a function you cannot write, so this is the other half of the call node.
library;

import 'package:flutter/material.dart';
import 'package:flutter_scene/visual_script.dart';

import '../shell/editor_theme.dart';
import '../shell/panel_chrome.dart';
import 'visual_script_layout.dart'
    show visualScriptCommentColors, visualScriptTypeColor;

/// The pin types a parameter or a variable can be given.
///
/// Exec is not among them: control flow is a wire, not a value, and a
/// parameter of that type would be a second exec input nobody could reach.
final List<VisualScriptType> declarableTypes = [
  for (final type in VisualScriptType.values)
    if (type != VisualScriptType.exec) type,
];

/// Edits the open graph: what it is called, whether it is pure, and the
/// values it takes and gives back.
class VisualScriptGraphDetails extends StatelessWidget {
  const VisualScriptGraphDetails({
    super.key,
    required this.graph,
    required this.onChanged,
  });

  final VisualScriptGraph graph;

  /// Called after any edit, so the panel can commit the whole graph.
  final VoidCallback onChanged;

  /// Whether this kind of graph is something anything can call.
  bool get _isCallable =>
      graph.kind == VisualScriptGraphKind.function ||
      graph.kind == VisualScriptGraphKind.macro;

  /// An id no parameter here already has.
  ///
  /// Generated rather than taken from the name, so renaming a parameter does
  /// not break the wires that land on it.
  String _freeId() {
    final taken = {
      for (final entry in [...graph.parameters, ...graph.results]) entry.id,
    };
    for (var i = 1; ; i++) {
      if (!taken.contains('p$i')) return 'p$i';
    }
  }

  /// A name no parameter in [list] already has.
  String _freeName(List<VisualScriptParameter> list) {
    final taken = {for (final entry in list) entry.name};
    if (!taken.contains('New')) return 'New';
    for (var i = 2; ; i++) {
      if (!taken.contains('New $i')) return 'New $i';
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
    children: [
      const SizedBox(height: 8),
      Text(
        graph.name.isEmpty ? 'Untitled graph' : graph.name,
        style: editorSubheadText,
      ),
      const SizedBox(height: 4),
      Text(graph.kind.label, style: editorMicroText),
      if (graph.kind == VisualScriptGraphKind.function) ...[
        const EditorSectionHeader(label: 'Behaviour'),
        EditorPropertyRow(
          label: 'Pure',
          tooltip:
              'A pure function changes nothing and runs whenever something '
              'reads one of its results, so its call node has no control '
              'pins. The promise is not checked.',
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              height: editorFieldHeight,
              child: Checkbox(
                value: graph.isPure,
                onChanged: (next) {
                  graph.isPure = next ?? false;
                  onChanged();
                },
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                side: const BorderSide(color: editorLineColor),
              ),
            ),
          ),
        ),
      ],
      if (_isCallable) ...[
        _ParameterSection(
          label: 'Inputs',
          empty: 'No parameters. A call node will have none to fill in.',
          entries: graph.parameters,
          onAdd: () {
            graph.parameters.add(
              VisualScriptParameter(
                id: _freeId(),
                name: _freeName(graph.parameters),
                type: VisualScriptType.number,
              ),
            );
            onChanged();
          },
          onChanged: onChanged,
        ),
        _ParameterSection(
          label: 'Outputs',
          empty: 'No results. A call node will hand nothing back.',
          entries: graph.results,
          onAdd: () {
            graph.results.add(
              VisualScriptParameter(
                id: _freeId(),
                name: _freeName(graph.results),
                type: VisualScriptType.number,
              ),
            );
            onChanged();
          },
          onChanged: onChanged,
        ),
      ] else
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'Only a function or a macro takes parameters. An event graph is '
            'entered by its events, and a construction script by being built.',
            style: editorMicroText,
          ),
        ),
    ],
  );
}

/// One list of parameters — the graph's inputs or its outputs.
class _ParameterSection extends StatelessWidget {
  const _ParameterSection({
    required this.label,
    required this.empty,
    required this.entries,
    required this.onAdd,
    required this.onChanged,
  });

  final String label;
  final String empty;
  final List<VisualScriptParameter> entries;
  final VoidCallback onAdd;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      EditorSectionHeader(
        label: label,
        trailing: EditorPanelIconButton(
          icon: Icons.add,
          tooltip: 'Add one',
          onPressed: onAdd,
        ),
      ),
      if (entries.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(empty, style: editorMicroText),
        )
      else
        for (var i = 0; i < entries.length; i++)
          _ParameterRow(
            key: ValueKey(entries[i].id),
            parameter: entries[i],
            // Replaced rather than mutated: a parameter is immutable so the
            // two ends of a call cannot be handed one that changes underneath
            // them mid-frame.
            onReplace: (next) {
              entries[i] = next;
              onChanged();
            },
            onRemove: () {
              entries.removeAt(i);
              onChanged();
            },
          ),
    ],
  );
}

class _ParameterRow extends StatefulWidget {
  const _ParameterRow({
    super.key,
    required this.parameter,
    required this.onReplace,
    required this.onRemove,
  });

  final VisualScriptParameter parameter;
  final ValueChanged<VisualScriptParameter> onReplace;
  final VoidCallback onRemove;

  @override
  State<_ParameterRow> createState() => _ParameterRowState();
}

class _ParameterRowState extends State<_ParameterRow> {
  late final TextEditingController _name = TextEditingController(
    text: widget.parameter.name,
  );
  bool _hovered = false;

  @override
  void didUpdateWidget(_ParameterRow old) {
    super.didUpdateWidget(old);
    if (widget.parameter.name != old.parameter.name &&
        widget.parameter.name != _name.text) {
      _name.text = widget.parameter.name;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: visualScriptTypeColor(widget.parameter.type),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            flex: 5,
            child: EditorTextField(
              controller: _name,
              onSubmit: (text) {
                final trimmed = text.trim();
                if (trimmed.isEmpty) {
                  _name.text = widget.parameter.name;
                  return;
                }
                widget.onReplace(
                  VisualScriptParameter(
                    id: widget.parameter.id,
                    name: trimmed,
                    type: widget.parameter.type,
                    defaultValue: widget.parameter.defaultValue,
                    doc: widget.parameter.doc,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 4,
            child: EditorDropdown<VisualScriptType>(
              value: widget.parameter.type,
              items: [
                for (final type in declarableTypes)
                  DropdownMenuItem(value: type, child: Text(type.label)),
              ],
              onChanged: (next) {
                if (next == null) return;
                widget.onReplace(
                  VisualScriptParameter(
                    id: widget.parameter.id,
                    name: widget.parameter.name,
                    type: next,
                    // The old default belonged to the old type, and keeping a
                    // string on a number pin would read back as zero.
                    doc: widget.parameter.doc,
                  ),
                );
              },
            ),
          ),
          SizedBox(
            width: 20,
            child: _hovered
                ? EditorPanelIconButton(
                    icon: Icons.close,
                    tooltip: 'Remove',
                    onPressed: widget.onRemove,
                  )
                : null,
          ),
        ],
      ),
    ),
  );
}

/// Edits a declared event: what it carries.
///
/// The declaration is the contract between the node that calls the event and
/// every node that listens for it, so this is the only place either end's
/// pins come from.
class VisualScriptEventDetails extends StatelessWidget {
  const VisualScriptEventDetails({
    super.key,
    required this.event,
    required this.onChanged,
  });

  final VisualScriptEventSpec event;
  final VoidCallback onChanged;

  String _freeId() {
    final taken = {for (final entry in event.parameters) entry.id};
    for (var i = 1; ; i++) {
      if (!taken.contains('a$i')) return 'a$i';
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
    children: [
      const SizedBox(height: 8),
      Text(event.name, style: editorSubheadText),
      const SizedBox(height: 4),
      Text(
        'Call Event raises this, and every On Event listening for it runs '
        'before the caller continues.',
        style: editorMicroText,
      ),
      _ParameterSection(
        label: 'Carries',
        empty: 'Nothing. The event is a bare notification.',
        entries: event.parameters,
        onAdd: () {
          event.parameters.add(
            VisualScriptParameter(
              id: _freeId(),
              name: 'Value',
              type: VisualScriptType.number,
            ),
          );
          onChanged();
        },
        onChanged: onChanged,
      ),
    ],
  );
}

/// Edits a comment box: what it says, and which colour it is.
class VisualScriptCommentDetails extends StatefulWidget {
  const VisualScriptCommentDetails({
    super.key,
    required this.comment,
    required this.onChanged,
    required this.onDelete,
  });

  final VisualScriptComment comment;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  State<VisualScriptCommentDetails> createState() =>
      _VisualScriptCommentDetailsState();
}

class _VisualScriptCommentDetailsState
    extends State<VisualScriptCommentDetails> {
  late final TextEditingController _text = TextEditingController(
    text: widget.comment.text,
  );

  @override
  void didUpdateWidget(VisualScriptCommentDetails old) {
    super.didUpdateWidget(old);
    if (widget.comment.id != old.comment.id) {
      _text.text = widget.comment.text;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
    children: [
      const SizedBox(height: 8),
      Text('Comment', style: editorSubheadText),
      const SizedBox(height: 4),
      Text(
        'A box drawn behind the nodes. Dragging its title bar takes whatever '
        'is inside along with it.',
        style: editorMicroText,
      ),
      const EditorSectionHeader(label: 'Comment'),
      EditorPropertyRow(
        label: 'Text',
        child: EditorTextField(
          controller: _text,
          onSubmit: (value) {
            widget.comment.text = value;
            widget.onChanged();
          },
        ),
      ),
      EditorPropertyRow(
        label: 'Colour',
        child: Row(
          children: [
            for (var i = 0; i < visualScriptCommentColors.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              _Swatch(
                color: visualScriptCommentColors[i],
                selected: widget.comment.color == i,
                onTap: () {
                  widget.comment.color = i;
                  widget.onChanged();
                },
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 10),
      EditorActionButton(
        label: 'Delete comment',
        icon: Icons.delete_outline,
        onPressed: widget.onDelete,
      ),
    ],
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: selected ? editorAccentColor : editorLineColor,
          width: selected ? 1.6 : 1,
        ),
      ),
    ),
  );
}

/// Edits one of the blueprint's variables: its type, its scope, and what it
/// starts as.
///
/// Adding a variable was always possible and it was always a Number starting
/// at zero, because nothing offered the other two questions.
class VisualScriptVariableDetails extends StatelessWidget {
  const VisualScriptVariableDetails({
    super.key,
    required this.variable,
    required this.onReplace,
  });

  final VisualScriptVariable variable;

  /// Called with the variable that should take this one's place.
  final ValueChanged<VisualScriptVariable> onReplace;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
    children: [
      const SizedBox(height: 8),
      Row(
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: visualScriptTypeColor(variable.type),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(child: Text(variable.name, style: editorSubheadText)),
        ],
      ),
      const EditorSectionHeader(label: 'Variable'),
      EditorPropertyRow(
        label: 'Type',
        child: EditorDropdown<VisualScriptType>(
          value: variable.type,
          items: [
            for (final type in declarableTypes)
              DropdownMenuItem(value: type, child: Text(type.label)),
          ],
          onChanged: (next) {
            if (next == null) return;
            onReplace(
              VisualScriptVariable(
                name: variable.name,
                type: next,
                scope: variable.scope,
              ),
            );
          },
        ),
      ),
      EditorPropertyRow(
        label: 'Scope',
        tooltip: 'Where it lives, and how long it lasts.',
        child: EditorDropdown<VisualScriptVariableScope>(
          value: variable.scope,
          items: [
            for (final scope in VisualScriptVariableScope.values)
              DropdownMenuItem(value: scope, child: Text(scope.label)),
          ],
          onChanged: (next) {
            if (next == null) return;
            onReplace(
              VisualScriptVariable(
                name: variable.name,
                type: variable.type,
                initial: variable.initial,
                scope: next,
              ),
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(_scopeDoc(variable.scope), style: editorMicroText),
      ),
    ],
  );
}

String _scopeDoc(VisualScriptVariableScope scope) => switch (scope) {
  VisualScriptVariableScope.flow =>
    'Lives for one run of one event, and is created by writing to it.',
  VisualScriptVariableScope.local =>
    'Lives for one call of one function, and is discarded when it returns.',
  VisualScriptVariableScope.graph => 'Shared by every graph in this blueprint.',
  VisualScriptVariableScope.object =>
    'Shared by everything attached to the same object in the scene.',
  VisualScriptVariableScope.scene => 'Shared by everything in the open scene.',
  VisualScriptVariableScope.application =>
    'Shared by the whole application, and reset when it quits.',
  VisualScriptVariableScope.saved =>
    'Like Application, but written somewhere that outlives the process.',
};
