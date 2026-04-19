import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:neosapien_assignment/core/theme/app_theme.dart';
import 'package:neosapien_assignment/di/service_locator.dart';
import 'package:neosapien_assignment/features/identity/presentation/bloc/identity_bloc.dart';
import 'package:neosapien_assignment/features/transfer/presentation/bloc/incoming_transfer_bloc.dart';
import 'package:neosapien_assignment/features/transfer/presentation/bloc/send_transfer_bloc.dart';
import 'package:neosapien_assignment/features/transfer/presentation/pages/home_page.dart';

class NeoSapienApp extends StatelessWidget {
  const NeoSapienApp({super.key, this.initialTransferId});

  final String? initialTransferId;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<IdentityBloc>(
          create: (_) => getIt<IdentityBloc>()..add(const BootstrapIdentity()),
        ),
        BlocProvider<SendTransferBloc>(
          create: (_) => getIt<SendTransferBloc>(),
        ),
        BlocProvider<IncomingTransferBloc>(
          create: (_) => getIt<IncomingTransferBloc>(),
        ),
      ],
      child: MaterialApp(
        title: 'NeoSapien Transfer',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: HomePage(initialTransferId: initialTransferId),
      ),
    );
  }
}
