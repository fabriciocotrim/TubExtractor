import 'package:flutter/material.dart';

import '../core/languages.dart';
import '../core/models.dart';
import 'motion.dart';

class FormatSelector extends StatelessWidget {
  const FormatSelector({super.key, required this.value, required this.onChanged});
  final OutputFormat value;
  final ValueChanged<OutputFormat> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final f in OutputFormat.values)
            _Pill(label: f.label, selected: f == value, onTap: () => onChanged(f)),
        ],
      );
}

/// One option as a pill of clear glass. The chosen one fills with the accent
/// (aqua in dark, coral in light) and gets an accent rim; the change fades
/// instead of jumping.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = BorderRadius.circular(22);
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: Motion.of(context, Motion.fast),
        curve: Motion.smoothOut,
        decoration: BoxDecoration(
          borderRadius: r,
          color: selected ? scheme.secondaryContainer : Colors.transparent,
          border: Border.all(color: selected ? scheme.primary : scheme.outline, width: selected ? 1.4 : 1),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Center(
                  widthFactor: 1,
                  child: Text(label, style: Theme.of(context).textTheme.labelLarge),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TimestampSelector extends StatelessWidget {
  const TimestampSelector({super.key, required this.value, required this.format, required this.onChanged});
  final TimestampMode value;
  final OutputFormat format;
  final ValueChanged<TimestampMode> onChanged;

  @override
  Widget build(BuildContext context) {
    // Fades and resizes when the format switches between the two cases.
    return Resize(
      child: SwapIn(
        scale: false,
        child: !format.supportsTimestampOption
            ? Text(
                key: const ValueKey('fixed'),
                '${format.label} já traz o tempo de cada trecho.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            : SlidingTabs<TimestampMode>(
                key: const ValueKey('choice'),
                options: const [
                  (TimestampMode.off, 'Sem tempo'),
                  (TimestampMode.on, 'Com tempo'),
                  (TimestampMode.both, 'Os dois'),
                ],
                value: value,
                onChanged: onChanged,
              ),
      ),
    );
  }
}

class LanguageField extends StatelessWidget {
  const LanguageField({super.key, required this.code, required this.onChanged});
  final String code;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        icon: const Icon(Icons.translate),
        label: Text('${languageName(code)} ($code)'),
        onPressed: () async {
          final picked = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => _LanguageSheet(current: code),
          );
          if (picked != null) onChanged(picked);
        },
      );
}

class _LanguageSheet extends StatefulWidget {
  const _LanguageSheet({required this.current});
  final String current;
  @override
  State<_LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends State<_LanguageSheet> {
  String q = '';

  String _fold(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áàâã]'), 'a')
      .replaceAll(RegExp('[éê]'), 'e')
      .replaceAll('í', 'i')
      .replaceAll(RegExp('[óôõ]'), 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c');

  @override
  Widget build(BuildContext context) {
    final list = languages
        .where((l) => q.isEmpty || _fold(l.name).contains(_fold(q)) || l.code.toLowerCase().contains(q.toLowerCase()))
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar idioma (nome ou código)'),
            onChanged: (v) => setState(() => q = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(list[i].name),
              trailing: Text(list[i].code),
              selected: list[i].code == widget.current,
              onTap: () => Navigator.pop(context, list[i].code),
            ),
          ),
        ),
      ]),
    );
  }
}

const limitOptions = [10, 25, 50, 100, 250, 500];

class LimitSelector extends StatelessWidget {
  const LimitSelector({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  // Outlined, like the other fields, instead of the old underlined dropdown.
  Widget build(BuildContext context) => DropdownMenu<int>(
        initialSelection: limitOptions.contains(value) ? value : 500,
        width: 200,
        requestFocusOnTap: false,
        dropdownMenuEntries: [for (final n in limitOptions) DropdownMenuEntry(value: n, label: '$n vídeos')],
        onSelected: (v) => v == null ? null : onChanged(v),
      );
}

class Labeled extends StatelessWidget {
  const Labeled(this.label, this.child, {super.key, this.help});
  final String label;
  final Widget child;

  /// Short explanation under the control.
  final String? help;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          child,
          if (help != null) ...[
            const SizedBox(height: 6),
            Text(help!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ]),
      );
}
