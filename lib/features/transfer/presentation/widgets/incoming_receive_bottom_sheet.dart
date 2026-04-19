import 'package:flutter/material.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/transfer.dart';
import 'package:neosapien_assignment/features/transfer/presentation/widgets/incoming_ui_helpers.dart';

Future<bool?> showIncomingReceiveBottomSheet(
  BuildContext context, {
  required Transfer transfer,
}) {
  final preview = transfer.senderUid.length > 10
      ? transfer.senderUid.substring(0, 10)
      : transfer.senderUid;
  final total = transfer.files.fold<int>(0, (a, f) => a + f.size);

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(24),
      ),
    ),
    builder: (sheetContext) {
      final bottom = MediaQuery.paddingOf(sheetContext).bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(28, 8, 28, bottom + 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'INCOMING TRANSFER',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'FROM ${preview.toUpperCase()} · ${transfer.files.length} FILES · ${IncomingUiHelpers.formatBytes(total)}',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white12,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('DECLINE'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('ACCEPT'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
