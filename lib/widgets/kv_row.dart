import 'package:flutter/material.dart';

Widget kvRow(String label, String value) {
  if (value.trim().isEmpty || value == 'null') {
    return const SizedBox.shrink();
  }

  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
