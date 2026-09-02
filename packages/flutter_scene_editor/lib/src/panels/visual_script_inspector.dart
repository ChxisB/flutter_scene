/// The panel beside the canvas that edits the selected node.
///
/// A graph is two kinds of information and the canvas can only show one of
/// them. Wires are shape, and belong on a canvas; the *values* typed into a
/// node — a delay's seconds, a switch's cases, which variable a Get reads —
/// are text, and belong in a column with labels. Without this the second kind
/// was unreachable: nothing in the editor wrote a node's literals at all, so
/// every node with something to type into it was decoration.
///
/// Nothing here knows what a scene is. It is handed a node, its type and the
/// graph around it, and reports edits back.
library;

import 'package:flutter/material.dart';
import 'package:flutter_scene/visual_script.dart';
import 'package:vector_math/vector_math.dart'
    show Quaternion, Vector2, Vector3, Vector4;

import '../shell/editor_theme.dart';
import '../shell/panel_chrome.dart';
import 'visual_script_layout.dart' show visualScriptTypeColor;

/// A value written into a node that is not a pin.
///
/// A pin's literal is what an unconnected input reads; a *setting* changes
/// what the node is — how many outputs a Sequence has, which cases a Switch
/// branches on, which store a Get Variable reads. They are literals too, in
/// the same map, but they never appear as a row on the node so the canvas has
/// nowhere to show them.
class VisualScriptSetting {
  const VisualScriptSetting({
    required this.key,
    required this.label,
    required this.type,
    this.doc = '',
    this.options = const [],
    this.defaultValue,
  });

  /// The literal key it reads and writes.
  final String key;

  /// What the row is called.
  final String label;

  /// Which editor to draw.
  final VisualScriptType type;

  /// One line under the section, when it needs explaining.
  final String doc;

  /// When non-empty, the setting is a choice between these rather than free
  /// text — the value written is the option itself.
  final List<String> options;

  /// What the row shows when nothing has been written yet.
  final Object? defaultValue;
}

/// The settings each node type has, keyed by node type id.
///
/// Here rather than on [VisualScriptNodeType] because it is entirely an
/// editing concern: the runtime reads these literals directly and has no use
/// for a label or a set of options.
final Map<String, List<VisualScriptSetting>> visualScriptSettings = {
  'flow.sequence': const [
    VisualScriptSetting(
      key: 'count',
      label: 'Outputs',
      type: VisualScriptType.integer,
      defaultValue: 3,
      doc: 'How many branches run in order.',
    ),
  ],
  'list.make': const [
    VisualScriptSetting(
      key: 'count',
      label: 'Items',
      type: VisualScriptType.integer,
      defaultValue: 3,
    ),
  ],
  'flow.switchString': const [_casesSetting],
  'flow.switchInteger': const [_casesSetting],
  'flow.select': const [_casesSetting],
  'var.get': [_scopeSetting],
  'var.set': [_scopeSetting],
};

const VisualScriptSetting _casesSetting = VisualScriptSetting(
  key: 'cases',
  label: 'Cases',
  type: VisualScriptType.list,
  doc: 'One branch per case, in order. Separate them with commas.',
);

final VisualScriptSetting _scopeSetting = VisualScriptSetting(
  key: 'scope',
  label: 'Scope',
  type: VisualScriptType.string,
  doc: 'Which store the variable lives in.',
  options: [for (final scope in VisualScriptVariableScope.values) scope.name],
  defaultValue: VisualScriptVariableScope.graph.name,
);

/// Edits one node's values, or says what to do when none is selected.
class VisualScriptInspector extends StatelessWidget {
  const VisualScriptInspector({
    super.key,
    required this.graph,
    required this.registry,
    required this.node,
    required this.onChanged,
    this.graphs,
  });

  final VisualScriptGraph graph;
  final VisualScriptRegistry registry;

  /// The selected node, or null.
  final VisualScriptNodeSpec? node;

  /// How a nesting node finds the graph it names.
  final VisualScriptGraphLookup? graphs;

  /// Called with the literal key and its new value. A null value clears it
  /// back to the pin's own default.
  final void Function(String key, Object? value) onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = node;
    if (selected == null) return const _NothingSelected();
    final type = registry[selected.type];
    if (type == null) return _UnknownType(id: selected.type);

    final settings = visualScriptSettings[type.id] ?? const [];
    // Only unwired inputs: a pin with a wire on it takes its value from the
    // wire, and offering a box that does nothing is worse than offering none.
    final editable = [
      for (final pin in type.inputsOf(selected, graphs))
        if (pin.type != VisualScriptType.exec &&
            graph.inputTo(selected.id, pin.id) == null)
          pin,
    ];
    final wired = [
      for (final pin in type.inputsOf(selected, graphs))
        if (pin.type != VisualScriptType.exec &&
            graph.inputTo(selected.id, pin.id) != null)
          pin,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      children: [
        const SizedBox(height: 8),
        Text(type.label, style: editorSubheadText),
        if (type.doc.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(type.doc, style: editorMicroText),
        ],
        if (settings.isNotEmpty) ...[
          const EditorSectionHeader(label: 'Settings'),
          for (final setting in settings)
            _SettingRow(
              setting: setting,
              value: selected.literals[setting.key] ?? setting.defaultValue,
              onChanged: (value) => onChanged(setting.key, value),
            ),
        ],
        if (editable.isNotEmpty) ...[
          const EditorSectionHeader(label: 'Inputs'),
          for (final pin in editable)
            _SettingRow(
              setting: VisualScriptSetting(
                key: pin.id,
                label: pin.label.isEmpty ? pin.id : pin.label,
                type: pin.type,
                doc: pin.doc,
                defaultValue: pin.defaultValue,
              ),
              value: selected.literals.containsKey(pin.id)
                  ? selected.literals[pin.id]
                  : pin.defaultValue,
              onChanged: (value) => onChanged(pin.id, value),
            ),
        ],
        if (wired.isNotEmpty) ...[
          const EditorSectionHeader(label: 'Wired'),
          for (final pin in wired)
            EditorPropertyRow(
              label: pin.label.isEmpty ? pin.id : pin.label,
              tooltip: 'Taken from the wire. Disconnect it to type a value.',
              child: Row(
                children: [
                  Icon(
                    Icons.link,
                    size: 12,
                    color: visualScriptTypeColor(pin.type),
                  ),
                  const SizedBox(width: 5),
                  Text(pin.type.label, style: editorMicroText),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// One editable value, drawn by what kind of value it is.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.setting,
    required this.value,
    required this.onChanged,
  });

  final VisualScriptSetting setting;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    return EditorPropertyRow(
      label: setting.label,
      tooltip: setting.doc.isEmpty ? null : setting.doc,
      child: _field(),
    );
  }

  /// How many numbers a value of this type is written as, or null when it is
  /// not written as numbers at all.
  int? get _components => switch (setting.type) {
    VisualScriptType.vector2 => 2,
    VisualScriptType.vector3 => 3,
    VisualScriptType.vector4 => 4,
    VisualScriptType.quaternion => 4,
    VisualScriptType.color => 4,
    _ => null,
  };

  Widget _field() {
    if (setting.options.isNotEmpty) {
      return EditorDropdown<String>(
        value: setting.options.contains('$value')
            ? '$value'
            : setting.options.first,
        items: [
          for (final option in setting.options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: (picked) => onChanged(picked),
      );
    }
    return switch (setting.type) {
      VisualScriptType.boolean => _BoolField(
        value: scriptBool(value),
        onChanged: onChanged,
      ),
      VisualScriptType.list => _TextField(
        // Written back as a list, so a Switch's cases stay a list of values
        // rather than becoming one string with commas in it.
        text: scriptList(value).map(scriptString).join(', '),
        hint: 'one, two, three',
        onSubmit: (text) => onChanged(_parseList(text)),
      ),
      VisualScriptType.integer => _TextField(
        text: value == null ? '' : '${scriptInteger(value)}',
        onSubmit: (text) =>
            onChanged(text.trim().isEmpty ? null : int.tryParse(text.trim())),
      ),
      VisualScriptType.number => _TextField(
        text: value == null ? '' : _number(scriptNumber(value)),
        onSubmit: (text) => onChanged(
          text.trim().isEmpty ? null : double.tryParse(text.trim()),
        ),
      ),
      _ when _components != null => _NumberRow(
        labels: _componentLabels,
        values: _componentValues,
        onChanged: (parts) => onChanged(_fromComponents(parts)),
      ),
      // Strings, node and asset references, and Any all take free text. Any
      // parses what it is handed, so a Print wired to nothing can still be
      // given the number 3 rather than the word "3".
      _ => _TextField(
        text: value == null ? '' : scriptString(value),
        onSubmit: (text) => onChanged(
          setting.type == VisualScriptType.any ? _parseLoose(text) : text,
        ),
      ),
    };
  }

  List<String> get _componentLabels => switch (setting.type) {
    VisualScriptType.color => const ['R', 'G', 'B', 'A'],
    VisualScriptType.quaternion => const ['X', 'Y', 'Z', 'W'],
    VisualScriptType.vector2 => const ['X', 'Y'],
    _ => const ['X', 'Y', 'Z', 'W'],
  };

  List<double> get _componentValues => switch (setting.type) {
    VisualScriptType.vector2 => [
      scriptVector2(value).x,
      scriptVector2(value).y,
    ],
    VisualScriptType.vector3 => [
      scriptVector(value).x,
      scriptVector(value).y,
      scriptVector(value).z,
    ],
    VisualScriptType.color => [
      scriptColor(value).x,
      scriptColor(value).y,
      scriptColor(value).z,
      scriptColor(value).w,
    ],
    VisualScriptType.quaternion => [
      scriptQuaternion(value).x,
      scriptQuaternion(value).y,
      scriptQuaternion(value).z,
      scriptQuaternion(value).w,
    ],
    _ => [
      scriptVector4(value).x,
      scriptVector4(value).y,
      scriptVector4(value).z,
      scriptVector4(value).w,
    ],
  };

  Object _fromComponents(List<double> p) => switch (setting.type) {
    VisualScriptType.vector2 => Vector2(p[0], p[1]),
    VisualScriptType.vector3 => Vector3(p[0], p[1], p[2]),
    VisualScriptType.quaternion => Quaternion(p[0], p[1], p[2], p[3]),
    _ => Vector4(p[0], p[1], p[2], p[3]),
  };
}

String _number(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(3);

/// Splits `one, two, 3` into a list, reading each part as what it looks like.
List<Object?> _parseList(String text) => [
  for (final part in text.split(','))
    if (part.trim().isNotEmpty) _parseLoose(part.trim()),
];

/// Reads text as the value it looks like, falling back to the text itself.
Object? _parseLoose(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed == 'true') return true;
  if (trimmed == 'false') return false;
  final number = num.tryParse(trimmed);
  if (number != null) return number is int ? number : number.toDouble();
  return text;
}

class _BoolField extends StatelessWidget {
  const _BoolField({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: SizedBox(
      height: editorFieldHeight,
      child: Checkbox(
        value: value,
        onChanged: (next) => onChanged(next ?? false),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: const BorderSide(color: editorLineColor),
      ),
    ),
  );
}

/// A text field that keeps its controller in step with the value behind it.
class _TextField extends StatefulWidget {
  const _TextField({required this.text, required this.onSubmit, this.hint});

  final String text;
  final String? hint;
  final ValueChanged<String> onSubmit;

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );

  @override
  void didUpdateWidget(_TextField old) {
    super.didUpdateWidget(old);
    // Only when the value behind it actually moved: assigning on every build
    // would fight whoever is typing.
    if (widget.text != old.text && widget.text != _controller.text) {
      _controller.text = widget.text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EditorTextField(
    controller: _controller,
    hint: widget.hint,
    onSubmit: widget.onSubmit,
  );
}

/// Two to four numbers on one row, for the values written as components.
class _NumberRow extends StatelessWidget {
  const _NumberRow({
    required this.labels,
    required this.values,
    required this.onChanged,
  });

  final List<String> labels;
  final List<double> values;
  final ValueChanged<List<double>> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < values.length; i++) ...[
        if (i > 0) const SizedBox(width: 4),
        // A plain Expanded in a plain Row: this is laid out against a bounded
        // width inside a property row, unlike a toolbar.
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 10,
                child: Text(labels[i], style: editorMicroText),
              ),
              Expanded(
                child: _TextField(
                  text: _number(values[i]),
                  onSubmit: (text) {
                    final parsed = double.tryParse(text.trim());
                    if (parsed == null) return;
                    onChanged([
                      for (var j = 0; j < values.length; j++)
                        j == i ? parsed : values[j],
                    ]);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}

class _NothingSelected extends StatelessWidget {
  const _NothingSelected();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(
      'Select a node to edit what is typed into it.',
      style: editorMicroText,
    ),
  );
}

class _UnknownType extends StatelessWidget {
  const _UnknownType({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(
      'This node is a "$id", which this build does not have. It is kept so '
      'the graph is not damaged by opening it.',
      style: editorMicroText.copyWith(color: editorWarningColor),
    ),
  );
}
