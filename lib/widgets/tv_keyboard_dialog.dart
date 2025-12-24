import 'package:flutter/material.dart';

class TvKeyboardDialog extends StatefulWidget {
  final String title;
  final String initialValue;
  final TvKeyboardLayout layout;

  const TvKeyboardDialog({
    Key? key,
    required this.title,
    required this.initialValue,
    required this.layout,
  }) : super(key: key);

  @override
  State<TvKeyboardDialog> createState() => _TvKeyboardDialogState();

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String initialValue,
    required TvKeyboardLayout layout,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => TvKeyboardDialog(title: title, initialValue: initialValue, layout: layout),
    );
  }
}

enum TvKeyboardLayout {
  text,
  number,
}

class _TvKeyboardDialogState extends State<TvKeyboardDialog> {
  late String _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    final keyRows = widget.layout == TvKeyboardLayout.number ? _numberRows() : _textRows();
    final dialogHeight = widget.layout == TvKeyboardLayout.number ? 360.0 : 440.0;

    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      content: FocusTraversalGroup(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 520, maxHeight: dialogHeight),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              _valueDisplay(context),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: keyRows
                        .asMap()
                        .entries
                        .map(
                          (entry) => Padding(
                            padding: EdgeInsets.only(bottom: entry.key == keyRows.length - 1 ? 0 : 6),
                            child: _keyRow(context, entry.value, autofocus: entry.key == 0),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_value),
          child: const Text('DONE'),
        ),
      ],
    );
  }

  Widget _valueDisplay(BuildContext context) {
    final display = _value.isEmpty ? ' ' : _value;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).cardColor,
      ),
      child: Text(
        display,
        style: Theme.of(context).textTheme.titleMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _keyRow(BuildContext context, List<_KeySpec> keys, {required bool autofocus}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: keys.asMap().entries.map((entry) {
        final index = entry.key;
        final spec = entry.value;
        final isFirst = autofocus && index == 0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: SizedBox(
            width: spec.width,
            height: 38,
            child: TextButton(
              autofocus: isFirst,
              onPressed: () => _onKeyPressed(spec),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
              child: Text(spec.label, textAlign: TextAlign.center),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  void _onKeyPressed(_KeySpec spec) {
    switch (spec.type) {
      case _KeyType.char:
        setState(() => _value += spec.value);
        return;
      case _KeyType.space:
        setState(() => _value += ' ');
        return;
      case _KeyType.backspace:
        if (_value.isNotEmpty) {
          setState(() => _value = _value.substring(0, _value.length - 1));
        }
        return;
      case _KeyType.clear:
        setState(() => _value = '');
        return;
      case _KeyType.done:
        Navigator.of(context).pop(_value);
        return;
      case _KeyType.cancel:
        Navigator.of(context).pop(null);
        return;
    }
  }

  List<List<_KeySpec>> _textRows() {
    return [
      _specs('1234567890'),
      _specs('QWERTYUIOP'),
      _specs('ASDFGHJKL'),
      _specs('ZXCVBNM'),
      _specs('ÇĞİÖŞÜ'),
      _specs('çğıöşü'),
      [
        _KeySpec(label: 'SPACE', type: _KeyType.space, value: '', width: 140),
        _KeySpec(label: 'BACK', type: _KeyType.backspace, value: '', width: 78),
        _KeySpec(label: 'CLEAR', type: _KeyType.clear, value: '', width: 78),
        _KeySpec(label: 'DONE', type: _KeyType.done, value: '', width: 78),
      ]
    ];
  }

  List<List<_KeySpec>> _numberRows() {
    return [
      _specs('123'),
      _specs('456'),
      _specs('789'),
      [
        _KeySpec(label: '-', type: _KeyType.char, value: '-', width: 56),
        _KeySpec(label: '0', type: _KeyType.char, value: '0', width: 56),
        _KeySpec(label: '.', type: _KeyType.char, value: '.', width: 56),
      ],
      [
        _KeySpec(label: 'BACK', type: _KeyType.backspace, value: '', width: 90),
        _KeySpec(label: 'CLEAR', type: _KeyType.clear, value: '', width: 90),
        _KeySpec(label: 'DONE', type: _KeyType.done, value: '', width: 90),
      ]
    ];
  }

  List<_KeySpec> _specs(String chars) {
    return chars
        .split('')
        .map((c) => _KeySpec(label: c, type: _KeyType.char, value: c, width: 38))
        .toList(growable: false);
  }
}

enum _KeyType {
  char,
  space,
  backspace,
  clear,
  done,
  cancel,
}

class _KeySpec {
  final String label;
  final _KeyType type;
  final String value;
  final double width;

  const _KeySpec({
    required this.label,
    required this.type,
    required this.value,
    required this.width,
  });
}
