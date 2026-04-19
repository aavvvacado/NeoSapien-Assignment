import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:neosapien_assignment/core/platform/native_download_saver.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/transfer.dart';
import 'package:neosapien_assignment/features/transfer/presentation/bloc/incoming_transfer_bloc.dart';
import 'package:neosapien_assignment/features/transfer/presentation/constants/incoming_ui_constants.dart';
import 'package:neosapien_assignment/features/transfer/presentation/widgets/incoming_common_widgets.dart';
import 'package:neosapien_assignment/features/transfer/presentation/widgets/incoming_receive_bottom_sheet.dart';
import 'package:neosapien_assignment/features/transfer/presentation/widgets/incoming_transfer_card.dart';
import 'package:neosapien_assignment/features/transfer/presentation/widgets/incoming_ui_helpers.dart';

class IncomingPage extends StatefulWidget {
  const IncomingPage({super.key});

  @override
  State<IncomingPage> createState() => _IncomingPageState();
}

class _IncomingPageState extends State<IncomingPage> {
  final NativeDownloadSaver _nativeBridge = NativeDownloadSaver();
  final ScrollController _scrollController = ScrollController();
  final Set<String> _expandedTransferIds = <String>{};
  final Set<String> _dismissedTransferIds = <String>{};
  bool _showCompleted = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutQuart,
      );
    }
  }

  void _toggleExpanded(String transferId) {
    setState(() {
      if (_expandedTransferIds.contains(transferId)) {
        _expandedTransferIds.remove(transferId);
      } else {
        _expandedTransferIds.add(transferId);
      }
    });
  }

  Future<void> _showReceiveDialog(
    BuildContext context,
    Transfer transfer,
  ) async {
    final bloc = context.read<IncomingTransferBloc>();
    final accepted = await showIncomingReceiveBottomSheet(context, transfer: transfer);
    if (accepted == true) {
      bloc.add(DownloadTransferRequested(transfer.transferId));
    } else if (accepted == false) {
      bloc.add(DeclineTransferRequested(transfer.transferId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<IncomingTransferBloc, IncomingTransferState>(
      listenWhen: (previous, current) =>
          current.downloadHandoff != null &&
          previous.downloadHandoff != current.downloadHandoff,
      listener: (context, state) {
        final handoff = state.downloadHandoff;
        if (handoff == null || handoff.saved.isEmpty) return;
        final primary = handoff.saved.first;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            dismissDirection: DismissDirection.horizontal,
            content: Text('Saved "${primary.fileName}"'),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () {
                _nativeBridge.openUriForView(
                  pathOrUri: primary.openUriOrPath,
                  fileName: primary.fileName,
                );
              },
            ),
          ),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          context.read<IncomingTransferBloc>().add(const ClearDownloadHandoff());
        });
      },
      builder: (context, state) {
        final sortedTransfers = IncomingUiHelpers.sortByPriority(state.transfers);
        final actionableCount =
            sortedTransfers.where((item) => IncomingUiHelpers.canReceive(item.status)).length;
        final completedCount =
            sortedTransfers.where((item) => item.status == TransferStatus.completed).length;
        final baseTransfers = _showCompleted
            ? sortedTransfers
            : sortedTransfers.where((item) => item.status != TransferStatus.completed).toList();
        final visibleTransfers = baseTransfers
            .where((item) => !_dismissedTransferIds.contains(item.transferId))
            .toList();

        return RefreshIndicator(
          onRefresh: () async {
            context.read<IncomingTransferBloc>().add(const ObserveIncomingStarted());
            await Future.delayed(const Duration(milliseconds: 800));
          },
          color: Colors.black,
          backgroundColor: Colors.white,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(IncomingUiConstants.pagePadding),
                  child: IncomingTopStatusCard(
                    lastSyncAt: state.lastSyncAt,
                    syncError: state.syncError,
                    totalTransfers: sortedTransfers.length,
                  ),
                ),
              ),
              if (actionableCount > 0)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: ActionRequiredHeaderDelegate(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    textColor: Theme.of(context).colorScheme.onPrimaryContainer,
                    count: actionableCount,
                    onTap: _scrollToTop,
                  ),
                ),
              if (state.message.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: IncomingUiConstants.pagePadding,
                      vertical: 4,
                    ),
                    child: IncomingUiHelpers.isTransientInfoMessage(state.message)
                        ? IncomingInfoBanner(message: state.message)
                        : IncomingErrorBanner(message: state.message),
                  ),
                ),
              if (state.syncError.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: IncomingUiConstants.pagePadding,
                      vertical: 4,
                    ),
                    child: IncomingErrorBanner(message: state.syncError),
                  ),
                ),
              if (!_showCompleted && completedCount > 0)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: IncomingUiConstants.pagePadding,
                      vertical: 4,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _showCompleted = true),
                        icon: const Icon(Icons.unfold_more),
                        label: Text('Show completed ($completedCount)'),
                      ),
                    ),
                  ),
                ),
              if (visibleTransfers.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: Text('No incoming transfers yet')),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: visibleTransfers.length,
                  itemBuilder: (context, index) {
                    final transfer = visibleTransfers[index];
                    final bloc = context.read<IncomingTransferBloc>();
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: IncomingUiConstants.pagePadding),
                      child: Dismissible(
                        key: Key(transfer.transferId),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        ),
                        onDismissed: (_) {
                          setState(() {
                            _dismissedTransferIds.add(transfer.transferId);
                          });
                          bloc.add(DeclineTransferRequested(transfer.transferId));
                        },
                        child: IncomingTransferCard(
                          transfer: transfer,
                          isExpanded: _expandedTransferIds.contains(transfer.transferId),
                          nativeBridge: _nativeBridge,
                          onToggleExpand: () => _toggleExpanded(transfer.transferId),
                          onReceive: () => _showReceiveDialog(context, transfer),
                          onDownloadAgain: transfer.status == TransferStatus.completed
                              ? () => bloc.add(DownloadTransferRequested(transfer.transferId))
                              : null,
                        ),
                      ),
                    );
                  },
                ),
              if (_showCompleted && completedCount > 0)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: IncomingUiConstants.pagePadding),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _showCompleted = false),
                        icon: const Icon(Icons.unfold_less),
                        label: const Text('Hide completed'),
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
            ],
          ),
        );
      },
    );
  }
}
