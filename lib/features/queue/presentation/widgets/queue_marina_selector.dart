import 'package:flutter/material.dart';

import '../../providers.dart';

class QueueMarinaSelector extends StatelessWidget {
  const QueueMarinaSelector({
    super.key,
    required this.state,
    required this.onChanged,
  });

  final QueueState state;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Marina',
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: state.selectedOption?.id,
          isExpanded: true,
          items: state.options
              .map(
                (option) => DropdownMenuItem<String>(
                  value: option.id,
                  child: Text(option.name),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
