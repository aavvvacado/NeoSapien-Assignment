import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:neosapien_assignment/di/service_locator.dart';
import 'package:neosapien_assignment/features/identity/presentation/bloc/identity_bloc.dart'
    show IdentityBloc, IdentityError, IdentityReady, IdentityState;
import 'package:neosapien_assignment/features/nearby/application/nearby_transport_service.dart';
import 'package:neosapien_assignment/features/transfer/presentation/bloc/incoming_transfer_bloc.dart';
import 'package:neosapien_assignment/features/transfer/presentation/pages/incoming_page.dart';
import 'package:neosapien_assignment/features/transfer/presentation/pages/send_page.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:path/path.dart' as p;
import 'package:neosapien_assignment/features/transfer/domain/entities/picked_attachment_meta.dart';
import 'package:neosapien_assignment/features/transfer/presentation/bloc/send_transfer_bloc.dart';
import 'dart:io';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.initialTransferId});

  final String? initialTransferId;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StreamSubscription? _intentDataStreamSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: (widget.initialTransferId ?? '').isNotEmpty ? 1 : 0,
    );

    if ((widget.initialTransferId ?? '').isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            dismissDirection: DismissDirection.horizontal,
            backgroundColor: Colors.white,
            content: Text(
              'Handing off transfer from notification...',
              style: TextStyle(color: Colors.black),
            ),
          ),
        );
      });
    }

    // For sharing images coming from outside the app while the app is in the memory
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      _handleSharedMedia(value);
    }, onError: (err) {
      print("getMediaStream error: $err");
    });

    // For sharing images coming from outside the app while the app is closed
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      _handleSharedMedia(value);
    });
  }

  void _handleSharedMedia(List<SharedMediaFile> media) {
    if (media.isEmpty) return;
    
    final attachments = media.map((f) {
      final file = File(f.path);
      return PickedAttachmentMeta(
        path: f.path,
        name: p.basename(f.path),
        size: file.existsSync() ? file.lengthSync() : 0,
      );
    }).toList();

    if (attachments.isNotEmpty) {
      context.read<SendTransferBloc>().add(ExternalFilesReceived(attachments));
      _tabController.animateTo(0);
    }
  }

  @override
  void dispose() {
    _intentDataStreamSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<IdentityBloc, IdentityState>(
      listenWhen: (previous, current) => current is IdentityReady,
      listener: (context, state) {
        if (state is IdentityReady) {
          context.read<IncomingTransferBloc>().add(const ObserveIncomingStarted());
          if (getIt.isRegistered<NearbyTransportService>()) {
            unawaited(getIt<NearbyTransportService>().startHost(state.identity.uid));
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'NeoSapien',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.5,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.wifi_tethering, size: 14, color: Color(0xFF3ECF8E)),
                          SizedBox(width: 6),
                          Text(
                            'Nearby Active',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _buildIdentitySection(),
              const SizedBox(height: 16),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    labelColor: Colors.black,
                    unselectedLabelColor: Colors.white38,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      fontSize: 12,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      fontSize: 12,
                    ),
                    tabs: const [
                      Tab(text: 'SEND'),
                      Tab(text: 'RECEIVE'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: const [
                    SendPage(),
                    IncomingPage(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdentitySection() {
    return BlocBuilder<IdentityBloc, IdentityState>(
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.08),
                  Colors.white.withOpacity(0.02),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'IDENTITY TOKEN',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                      ),
                    ),
                    if (state is IdentityReady)
                      const Icon(
                        Icons.verified_user_outlined,
                        color: Colors.white24,
                        size: 14,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        state is IdentityReady ? state.identity.shortCode : '••••••',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    _buildCopyButton(state),
                  ],
                ),
                if (state is IdentityError)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      state.message,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
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

  Widget _buildCopyButton(IdentityState state) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: state is IdentityReady
            ? () {
                Clipboard.setData(ClipboardData(text: state.identity.shortCode)).then((_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Token secured to clipboard',
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                        ),
                        backgroundColor: Colors.white,
                        behavior: SnackBarBehavior.floating,
                        dismissDirection: DismissDirection.horizontal,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                });
              }
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.copy_all_rounded,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
