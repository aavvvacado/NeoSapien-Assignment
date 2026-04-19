import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:neosapien_assignment/features/transfer/presentation/bloc/send_transfer_bloc.dart';
import 'package:neosapien_assignment/features/transfer/presentation/widgets/play_store_flower_progress.dart';
import 'package:neosapien_assignment/features/transfer/presentation/widgets/send_ui_helpers.dart';
import 'package:neosapien_assignment/features/transfer/presentation/widgets/transfer_rail_progress.dart';
import 'package:neosapien_assignment/features/transfer/presentation/widgets/transfer_surface_card.dart';

class SendPage extends StatefulWidget {
  const SendPage({super.key});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  final TextEditingController _recipientController = TextEditingController();

  @override
  void dispose() {
    _recipientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SendTransferBloc, SendTransferState>(
      builder: (context, state) {
        final uploading = state.status == SendTransferStatus.uploading;
        final p = state.transferProgress.clamp(0.0, 1.0);
        final showFlower =
            uploading || (state.totalBytes > 0 && p > 0 && p < 1);

        return BlocListener<SendTransferBloc, SendTransferState>(
          listenWhen: (prev, curr) =>
              curr.message == 'LARGE_TRANSFER_ON_CELLULAR',
          listener: (context, state) {
            _showCellularWarningDialog(context);
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInputCard(context, state),
                const SizedBox(height: 16),
                if (state.status == SendTransferStatus.validating)
                  _buildSimpleStatus('Checking recipient code...'),
                if (state.message.isNotEmpty &&
                    state.message != 'LARGE_TRANSFER_ON_CELLULAR')
                  _buildMessageBanner(state.message),
                if (state.status == SendTransferStatus.uploading ||
                    state.status == SendTransferStatus.validating)
                  _buildProgressCard(context, state, showFlower, p),
                const SizedBox(height: 16),
                const Opacity(
                  opacity: 0.3,
                  child: Text(
                    'Transfers are point-to-point and encrypted and ephemeral. Files expire in 24 hours.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInputCard(BuildContext context, SendTransferState state) {
    return TransferSurfaceCard(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RECIPIENT TOKEN',
            style: TextStyle(
              color: Colors.white24,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _recipientController,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 24,
              letterSpacing: 2,
              fontFamily: 'monospace',
              color: Colors.white,
            ),
            decoration: InputDecoration(
              hintText: '••••••',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.05)),
              counterText: '',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            maxLength: 8,
            onChanged: (value) => context.read<SendTransferBloc>().add(
              RecipientCodeChanged(value),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: Material(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () => context.read<SendTransferBloc>().add(
                      const PickFilesRequested(),
                    ),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      alignment: Alignment.center,
                      child: const Text(
                        'PICK FILES',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () => context.read<SendTransferBloc>().add(
                      const StartUploadRequested(),
                    ),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      alignment: Alignment.center,
                      child: Text(
                        state.status == SendTransferStatus.failed
                            ? 'RETRY'
                            : 'SEND',
                        style: TextStyle(
                          color: state.status == SendTransferStatus.failed
                              ? Colors.redAccent
                              : Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (state.status == SendTransferStatus.uploading)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Center(
                child: TextButton(
                  onPressed: () => context.read<SendTransferBloc>().add(
                    const CancelTransferRequested(),
                  ),
                  child: const Text(
                    'ABORT TRANSFER',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressCard(
    BuildContext context,
    SendTransferState state,
    bool showFlower,
    double p,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TransferSurfaceCard(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Row(
              children: [
                if (showFlower)
                  PlayStoreFlowerProgress(
                    active: true,
                    value: p <= 0.02 ? null : p,
                    size: 40,
                    color: Colors.white,
                  )
                else
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    color: Color(0xFF3ECF8E),
                    size: 40,
                  ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.status == SendTransferStatus.sent
                            ? 'MISSION SUCCESS'
                            : 'DATA UPLINK',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${SendUiHelpers.formatBytes(state.totalBytes)} · ETA ${SendUiHelpers.formatEta(state)}',
                        style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            TransferRailProgress(
              value: p.clamp(0.0, 1.0),
              backgroundColor: Colors.white10,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleStatus(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBanner(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Text(
          message,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  void _showCellularWarningDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Colors.white10),
        ),
        title: const Text(
          'Cellular Data Warning',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'You are about to transfer a large amount of data over a cellular connection. This may consume your data quota.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'CANCEL',
              style: TextStyle(
                color: Colors.white38,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () {
                Navigator.pop(dialogContext);
                // We'll need a "ForceStartUpload" or similar,
                // but for now we'll just reinvoke StartUpload
                // and we'd need a way to bypass the check.
                // I'll add a bypass to the event.
                context.read<SendTransferBloc>().add(
                  const StartUploadRequested(ignoreCellularWarning: true),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: const Text(
                  'CONTINUE',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
