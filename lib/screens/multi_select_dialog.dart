import 'package:flutter/material.dart';

class MultiSelectSearchDialog<T> extends StatefulWidget {
  final String title;
  final List<T> items;
  final Set<T> initialSelected;
  final String Function(T) itemLabel;

  const MultiSelectSearchDialog({
    Key? key,
    required this.title,
    required this.items,
    required this.initialSelected,
    required this.itemLabel,
  }) : super(key: key);

  @override
  _MultiSelectSearchDialogState<T> createState() => _MultiSelectSearchDialogState<T>();
}

class _MultiSelectSearchDialogState<T> extends State<MultiSelectSearchDialog<T>> {
  late Set<T> _selected;
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initialSelected);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items.where((i) {
      final label = widget.itemLabel(i).toLowerCase();
      return label.contains(_searchQuery.toLowerCase());
    }).toList();

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (val) {
                setState(() => _searchQuery = val);
              },
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (ctx, idx) {
                  final item = filtered[idx];
                  final isChecked = _selected.contains(item);
                  return CheckboxListTile(
                    title: Text(widget.itemLabel(item)),
                    value: isChecked,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selected.add(item);
                        } else {
                          _selected.remove(item);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}
