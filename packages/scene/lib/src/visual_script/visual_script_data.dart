/// Text and collections: the nodes for building a label, keeping a list, and
/// looking something up.
///
/// A graph without these can move things and cannot describe them. Everything
/// here is pure — pulled for a value, never reached by control flow — except
/// the handful that change a collection in place, which take an exec pin so
/// the order of the change is something the author decided rather than
/// something the pull order happened to produce.
library;

import 'visual_script_graph.dart';
import 'visual_script_runtime.dart';

VisualScriptResult _out(Map<String, Object?> outputs) =>
    (outputs: outputs, next: const <String>[]);
VisualScriptResult _then(Map<String, Object?> outputs) =>
    (outputs: outputs, next: const <String>['then']);

const VisualScriptPin _execIn = VisualScriptPin(
  id: 'exec',
  label: '',
  type: VisualScriptType.exec,
);
const VisualScriptPin _execOut = VisualScriptPin(
  id: 'then',
  label: '',
  type: VisualScriptType.exec,
  isInput: false,
);

VisualScriptPin _in(
  String id,
  String label,
  VisualScriptType type, {
  Object? defaultValue,
  String doc = '',
}) => VisualScriptPin(
  id: id,
  label: label,
  type: type,
  defaultValue: defaultValue,
  doc: doc,
);

VisualScriptPin _outPin(String id, String label, VisualScriptType type) =>
    VisualScriptPin(id: id, label: label, type: type, isInput: false);

// ---------------------------------------------------------------------------
// Text.
// ---------------------------------------------------------------------------

/// A pure node over one string.
VisualScriptNodeType _stringUnary(
  String id,
  String label,
  String doc,
  Object Function(String a) compute, {
  VisualScriptType result = VisualScriptType.string,
}) => VisualScriptNodeType(
  id: id,
  label: label,
  category: 'Text',
  doc: doc,
  pins: [
    _in('a', 'Text', VisualScriptType.string, defaultValue: ''),
    _outPin('value', 'Value', result),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': compute(scriptString(inputs['a']))}),
);

final VisualScriptNodeType joinText = VisualScriptNodeType(
  id: 'text.join',
  label: 'Join Text',
  category: 'Text',
  doc: 'Runs two pieces of text together, with an optional separator.',
  pins: [
    _in('a', 'A', VisualScriptType.any, defaultValue: ''),
    _in('b', 'B', VisualScriptType.any, defaultValue: ''),
    _in('separator', 'Separator', VisualScriptType.string, defaultValue: ''),
    _outPin('value', 'Value', VisualScriptType.string),
  ],
  evaluate: (context, node, inputs) => _out({
    'value':
        '${scriptString(inputs['a'])}${scriptString(inputs['separator'])}'
        '${scriptString(inputs['b'])}',
  }),
);

final VisualScriptNodeType formatText = VisualScriptNodeType(
  id: 'text.format',
  label: 'Format Text',
  category: 'Text',
  doc:
      'Fills {0}, {1}, {2} in a template with the values wired to it. The one '
      'to use for a label rather than a chain of Joins.',
  pins: [
    _in('template', 'Template', VisualScriptType.string, defaultValue: '{0}'),
    _in('0', 'Value 0', VisualScriptType.any),
    _in('1', 'Value 1', VisualScriptType.any),
    _in('2', 'Value 2', VisualScriptType.any),
    _outPin('value', 'Value', VisualScriptType.string),
  ],
  evaluate: (context, node, inputs) {
    var out = scriptString(inputs['template']);
    for (var i = 0; i < 3; i++) {
      // Only substitute a slot the graph actually filled, so an unused {1}
      // stays visible rather than quietly becoming the word "null".
      if (inputs['$i'] == null) continue;
      out = out.replaceAll('{$i}', scriptString(inputs['$i']));
    }
    return _out({'value': out});
  },
);

final VisualScriptNodeType textLength = _stringUnary(
  'text.length',
  'Text Length',
  'How many characters it has.',
  (a) => a.length,
  result: VisualScriptType.integer,
);

final VisualScriptNodeType upperCase = _stringUnary(
  'text.upper',
  'To Upper Case',
  'The same text in capitals.',
  (a) => a.toUpperCase(),
);

final VisualScriptNodeType lowerCase = _stringUnary(
  'text.lower',
  'To Lower Case',
  'The same text in lower case.',
  (a) => a.toLowerCase(),
);

final VisualScriptNodeType trimText = _stringUnary(
  'text.trim',
  'Trim',
  'Drops the spaces at either end.',
  (a) => a.trim(),
);

final VisualScriptNodeType textContains = VisualScriptNodeType(
  id: 'text.contains',
  label: 'Text Contains',
  category: 'Text',
  doc: 'Whether one piece of text appears inside another.',
  pins: [
    _in('a', 'Text', VisualScriptType.string, defaultValue: ''),
    _in('search', 'Contains', VisualScriptType.string, defaultValue: ''),
    _outPin('value', 'Value', VisualScriptType.boolean),
  ],
  evaluate: (context, node, inputs) => _out({
    'value': scriptString(inputs['a']).contains(scriptString(inputs['search'])),
  }),
);

final VisualScriptNodeType replaceText = VisualScriptNodeType(
  id: 'text.replace',
  label: 'Replace Text',
  category: 'Text',
  doc: 'Swaps every occurrence of one piece of text for another.',
  pins: [
    _in('a', 'Text', VisualScriptType.string, defaultValue: ''),
    _in('find', 'Find', VisualScriptType.string, defaultValue: ''),
    _in('replace', 'Replace With', VisualScriptType.string, defaultValue: ''),
    _outPin('value', 'Value', VisualScriptType.string),
  ],
  evaluate: (context, node, inputs) {
    final find = scriptString(inputs['find']);
    // Replacing the empty string would insert between every character.
    if (find.isEmpty) return _out({'value': scriptString(inputs['a'])});
    return _out({
      'value': scriptString(
        inputs['a'],
      ).replaceAll(find, scriptString(inputs['replace'])),
    });
  },
);

final VisualScriptNodeType splitText = VisualScriptNodeType(
  id: 'text.split',
  label: 'Split Text',
  category: 'Text',
  doc: 'Breaks text into a list, wherever the separator appears.',
  pins: [
    _in('a', 'Text', VisualScriptType.string, defaultValue: ''),
    _in('separator', 'Separator', VisualScriptType.string, defaultValue: ','),
    _outPin('value', 'Value', VisualScriptType.list),
  ],
  evaluate: (context, node, inputs) {
    final separator = scriptString(inputs['separator']);
    final text = scriptString(inputs['a']);
    return _out({
      'value': separator.isEmpty
          ? <Object?>[text]
          : text.split(separator).cast<Object?>().toList(),
    });
  },
);

final VisualScriptNodeType textToNumber = VisualScriptNodeType(
  id: 'text.toNumber',
  label: 'Text To Number',
  category: 'Text',
  doc: 'Reads a number out of text, or gives the fallback when it is not one.',
  pins: [
    _in('a', 'Text', VisualScriptType.string, defaultValue: ''),
    _in('fallback', 'Or', VisualScriptType.number, defaultValue: 0.0),
    _outPin('value', 'Value', VisualScriptType.number),
    _outPin('ok', 'Was A Number', VisualScriptType.boolean),
  ],
  evaluate: (context, node, inputs) {
    final parsed = double.tryParse(scriptString(inputs['a']).trim());
    return _out({
      'value': parsed ?? scriptNumber(inputs['fallback']),
      'ok': parsed != null,
    });
  },
);

final VisualScriptNodeType valueToText = VisualScriptNodeType(
  id: 'text.fromValue',
  label: 'To Text',
  category: 'Text',
  doc: 'Writes any value out as text, the way Print would show it.',
  pins: [
    _in('a', 'Value', VisualScriptType.any),
    _outPin('value', 'Value', VisualScriptType.string),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': scriptString(inputs['a'])}),
);

// ---------------------------------------------------------------------------
// Lists.
// ---------------------------------------------------------------------------

final VisualScriptNodeType makeList = VisualScriptNodeType(
  id: 'list.make',
  label: 'Make List',
  category: 'List',
  doc: 'Builds a list out of the values wired to it.',
  pins: [
    _in('0', 'Item 0', VisualScriptType.any),
    _in('1', 'Item 1', VisualScriptType.any),
    _in('2', 'Item 2', VisualScriptType.any),
    _outPin('value', 'Value', VisualScriptType.list),
  ],
  pinsFor: (node, graphs) {
    final count = scriptInteger(node.literals['count'], 3).clamp(1, 32);
    return [
      for (var i = 0; i < count; i++)
        _in('$i', 'Item $i', VisualScriptType.any),
      _outPin('value', 'Value', VisualScriptType.list),
    ];
  },
  evaluate: (context, node, inputs) {
    final count = scriptInteger(node.literals['count'], 3).clamp(1, 32);
    return _out({
      'value': [for (var i = 0; i < count; i++) inputs['$i']],
    });
  },
);

final VisualScriptNodeType listCount = VisualScriptNodeType(
  id: 'list.count',
  label: 'List Count',
  category: 'List',
  doc: 'How many items are in it.',
  pins: [
    _in('list', 'List', VisualScriptType.list),
    _outPin('value', 'Count', VisualScriptType.integer),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': scriptList(inputs['list']).length}),
);

final VisualScriptNodeType listItemAt = VisualScriptNodeType(
  id: 'list.get',
  label: 'Get Item',
  category: 'List',
  doc:
      'The item at an index. An index outside the list gives nothing rather '
      'than stopping the graph.',
  pins: [
    _in('list', 'List', VisualScriptType.list),
    _in('index', 'Index', VisualScriptType.integer, defaultValue: 0),
    _outPin('value', 'Item', VisualScriptType.any),
    _outPin('found', 'In Range', VisualScriptType.boolean),
  ],
  evaluate: (context, node, inputs) {
    final items = scriptList(inputs['list']);
    final index = scriptInteger(inputs['index']);
    final inRange = index >= 0 && index < items.length;
    return _out({'value': inRange ? items[index] : null, 'found': inRange});
  },
);

final VisualScriptNodeType listContains = VisualScriptNodeType(
  id: 'list.contains',
  label: 'List Contains',
  category: 'List',
  doc: 'Whether the list holds this value.',
  pins: [
    _in('list', 'List', VisualScriptType.list),
    _in('item', 'Item', VisualScriptType.any),
    _outPin('value', 'Value', VisualScriptType.boolean),
    _outPin('index', 'First At', VisualScriptType.integer),
  ],
  evaluate: (context, node, inputs) {
    final index = scriptList(inputs['list']).indexOf(inputs['item']);
    return _out({'value': index >= 0, 'index': index});
  },
);

final VisualScriptNodeType addToList = VisualScriptNodeType(
  id: 'list.add',
  label: 'Add To List',
  category: 'List',
  doc: 'Puts an item on the end. Gives back the same list, now longer.',
  pins: [
    _execIn,
    _in('list', 'List', VisualScriptType.list),
    _in('item', 'Item', VisualScriptType.any),
    _execOut,
    _outPin('value', 'List', VisualScriptType.list),
  ],
  evaluate: (context, node, inputs) {
    final items = scriptList(inputs['list'])..add(inputs['item']);
    return _then({'value': items});
  },
);

final VisualScriptNodeType removeFromList = VisualScriptNodeType(
  id: 'list.remove',
  label: 'Remove From List',
  category: 'List',
  doc: 'Takes the first matching item out, if it is there.',
  pins: [
    _execIn,
    _in('list', 'List', VisualScriptType.list),
    _in('item', 'Item', VisualScriptType.any),
    _execOut,
    _outPin('value', 'List', VisualScriptType.list),
    _outPin('removed', 'Was There', VisualScriptType.boolean),
  ],
  evaluate: (context, node, inputs) {
    final items = scriptList(inputs['list']);
    final removed = items.remove(inputs['item']);
    return _then({'value': items, 'removed': removed});
  },
);

final VisualScriptNodeType clearList = VisualScriptNodeType(
  id: 'list.clear',
  label: 'Clear List',
  category: 'List',
  doc: 'Empties it.',
  pins: [
    _execIn,
    _in('list', 'List', VisualScriptType.list),
    _execOut,
    _outPin('value', 'List', VisualScriptType.list),
  ],
  evaluate: (context, node, inputs) {
    final items = scriptList(inputs['list'])..clear();
    return _then({'value': items});
  },
);

final VisualScriptNodeType reverseList = VisualScriptNodeType(
  id: 'list.reverse',
  label: 'Reverse List',
  category: 'List',
  doc: 'A copy in the opposite order. The original is left alone.',
  pins: [
    _in('list', 'List', VisualScriptType.list),
    _outPin('value', 'Value', VisualScriptType.list),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': scriptList(inputs['list']).reversed.toList()}),
);

final VisualScriptNodeType mergeLists = VisualScriptNodeType(
  id: 'list.merge',
  label: 'Merge Lists',
  category: 'List',
  doc: 'A new list with everything from both, in order.',
  pins: [
    _in('a', 'A', VisualScriptType.list),
    _in('b', 'B', VisualScriptType.list),
    _outPin('value', 'Value', VisualScriptType.list),
  ],
  evaluate: (context, node, inputs) => _out({
    'value': [...scriptList(inputs['a']), ...scriptList(inputs['b'])],
  }),
);

// ---------------------------------------------------------------------------
// Dictionaries.
// ---------------------------------------------------------------------------

final VisualScriptNodeType makeDictionary = VisualScriptNodeType(
  id: 'dict.make',
  label: 'Make Dictionary',
  category: 'Dictionary',
  doc: 'An empty dictionary to put things in.',
  pins: [_outPin('value', 'Value', VisualScriptType.dictionary)],
  evaluate: (context, node, inputs) => _out({'value': <String, Object?>{}}),
);

final VisualScriptNodeType dictionaryGet = VisualScriptNodeType(
  id: 'dict.get',
  label: 'Get From Dictionary',
  category: 'Dictionary',
  doc: 'What is stored under a key, and whether anything was.',
  pins: [
    _in('dictionary', 'Dictionary', VisualScriptType.dictionary),
    _in('key', 'Key', VisualScriptType.string, defaultValue: ''),
    _outPin('value', 'Value', VisualScriptType.any),
    _outPin('found', 'Found', VisualScriptType.boolean),
  ],
  evaluate: (context, node, inputs) {
    final map = scriptMap(inputs['dictionary']);
    final key = scriptString(inputs['key']);
    return _out({'value': map[key], 'found': map.containsKey(key)});
  },
);

final VisualScriptNodeType dictionarySet = VisualScriptNodeType(
  id: 'dict.set',
  label: 'Set In Dictionary',
  category: 'Dictionary',
  doc: 'Stores a value under a key, replacing whatever was there.',
  pins: [
    _execIn,
    _in('dictionary', 'Dictionary', VisualScriptType.dictionary),
    _in('key', 'Key', VisualScriptType.string, defaultValue: ''),
    _in('value', 'Value', VisualScriptType.any),
    _execOut,
    _outPin('out', 'Dictionary', VisualScriptType.dictionary),
  ],
  evaluate: (context, node, inputs) {
    final map = scriptMap(inputs['dictionary']);
    map[scriptString(inputs['key'])] = inputs['value'];
    return _then({'out': map});
  },
);

final VisualScriptNodeType dictionaryRemove = VisualScriptNodeType(
  id: 'dict.remove',
  label: 'Remove From Dictionary',
  category: 'Dictionary',
  doc: 'Takes a key out.',
  pins: [
    _execIn,
    _in('dictionary', 'Dictionary', VisualScriptType.dictionary),
    _in('key', 'Key', VisualScriptType.string, defaultValue: ''),
    _execOut,
    _outPin('out', 'Dictionary', VisualScriptType.dictionary),
    _outPin('removed', 'Was There', VisualScriptType.boolean),
  ],
  evaluate: (context, node, inputs) {
    final map = scriptMap(inputs['dictionary']);
    final key = scriptString(inputs['key']);
    final had = map.containsKey(key);
    map.remove(key);
    return _then({'out': map, 'removed': had});
  },
);

final VisualScriptNodeType dictionaryHas = VisualScriptNodeType(
  id: 'dict.contains',
  label: 'Dictionary Contains',
  category: 'Dictionary',
  doc: 'Whether a key is in it.',
  pins: [
    _in('dictionary', 'Dictionary', VisualScriptType.dictionary),
    _in('key', 'Key', VisualScriptType.string, defaultValue: ''),
    _outPin('value', 'Value', VisualScriptType.boolean),
  ],
  evaluate: (context, node, inputs) => _out({
    'value': scriptMap(
      inputs['dictionary'],
    ).containsKey(scriptString(inputs['key'])),
  }),
);

final VisualScriptNodeType dictionaryKeys = VisualScriptNodeType(
  id: 'dict.keys',
  label: 'Dictionary Keys',
  category: 'Dictionary',
  doc: 'Its keys, as a list to walk.',
  pins: [
    _in('dictionary', 'Dictionary', VisualScriptType.dictionary),
    _outPin('value', 'Keys', VisualScriptType.list),
    _outPin('count', 'Count', VisualScriptType.integer),
  ],
  evaluate: (context, node, inputs) {
    final keys = scriptMap(inputs['dictionary']).keys.cast<Object?>().toList();
    return _out({'value': keys, 'count': keys.length});
  },
);

final VisualScriptNodeType dictionaryValues = VisualScriptNodeType(
  id: 'dict.values',
  label: 'Dictionary Values',
  category: 'Dictionary',
  doc: 'Its values, as a list to walk.',
  pins: [
    _in('dictionary', 'Dictionary', VisualScriptType.dictionary),
    _outPin('value', 'Values', VisualScriptType.list),
  ],
  evaluate: (context, node, inputs) =>
      _out({'value': scriptMap(inputs['dictionary']).values.toList()}),
);

/// Every text, list and dictionary node here.
/// {@category Visual scripting}
final List<VisualScriptNodeType> dataVisualScriptNodes = [
  joinText,
  formatText,
  textLength,
  upperCase,
  lowerCase,
  trimText,
  textContains,
  replaceText,
  splitText,
  textToNumber,
  valueToText,
  makeList,
  listCount,
  listItemAt,
  listContains,
  addToList,
  removeFromList,
  clearList,
  reverseList,
  mergeLists,
  makeDictionary,
  dictionaryGet,
  dictionarySet,
  dictionaryRemove,
  dictionaryHas,
  dictionaryKeys,
  dictionaryValues,
];
