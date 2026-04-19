import 'package:get_it/get_it.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:neosapien_assignment/app/bootstrap.dart';
import 'package:neosapien_assignment/core/services/cache_cleanup_service.dart';
import 'package:neosapien_assignment/core/platform/native_download_saver.dart';
import 'package:neosapien_assignment/core/platform/android_transfer_service.dart';
import 'package:neosapien_assignment/core/platform/android_transfer_recovery_scheduler.dart';
import 'package:neosapien_assignment/core/platform/android_incoming_notification_service.dart';
import 'package:neosapien_assignment/features/files/data/local_file_picker_service.dart';
import 'package:neosapien_assignment/features/identity/data/datasources/supabase_identity_datasource.dart';
import 'package:neosapien_assignment/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:neosapien_assignment/features/identity/data/repositories/identity_repository_unconfigured.dart';
import 'package:neosapien_assignment/features/identity/domain/repositories/identity_repository.dart';
import 'package:neosapien_assignment/features/identity/domain/usecases/bootstrap_identity_usecase.dart';
import 'package:neosapien_assignment/features/identity/presentation/bloc/identity_bloc.dart';
import 'package:neosapien_assignment/features/nearby/application/nearby_transport_service.dart';
import 'package:neosapien_assignment/features/transfer/data/datasources/supabase_transfer_datasource.dart';
import 'package:neosapien_assignment/features/transfer/data/repositories/transfer_repository_impl.dart';
import 'package:neosapien_assignment/features/transfer/data/repositories/transfer_repository_unconfigured.dart';
import 'package:neosapien_assignment/features/transfer/domain/repositories/transfer_repository.dart';
import 'package:neosapien_assignment/features/transfer/domain/usecases/observe_incoming_transfers_usecase.dart';
import 'package:neosapien_assignment/features/transfer/domain/usecases/send_transfer_usecase.dart';
import 'package:neosapien_assignment/features/transfer/presentation/bloc/incoming_transfer_bloc.dart';
import 'package:neosapien_assignment/features/transfer/presentation/bloc/send_transfer_bloc.dart';

final GetIt getIt = GetIt.instance;

Future<void> setupServiceLocator() async {
  if (getIt.isRegistered<IdentityBloc>()) {
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(prefs);
  getIt.registerLazySingleton<NativeDownloadSaver>(() => NativeDownloadSaver());
  getIt.registerLazySingleton<AndroidTransferService>(
    () => AndroidTransferService(),
  );
  getIt.registerLazySingleton<AndroidTransferRecoveryScheduler>(
    () => AndroidTransferRecoveryScheduler(),
  );
  getIt.registerLazySingleton<AndroidIncomingNotificationService>(
    () => AndroidIncomingNotificationService(),
  );
  getIt.registerLazySingleton<LocalFilePickerService>(
    () => LocalFilePickerService(nativeBridge: getIt<NativeDownloadSaver>()),
  );
  getIt.registerLazySingleton<CacheCleanupService>(
    () => const CacheCleanupService(),
  );

  if (isSupabaseReady) {
    getIt.registerLazySingleton<SupabaseClient>(() => Supabase.instance.client);
    getIt.registerLazySingleton<SupabaseIdentityDataSource>(
      () => SupabaseIdentityDataSource(
        supabaseClient: getIt<SupabaseClient>(),
        prefs: getIt<SharedPreferences>(),
      ),
    );
    getIt.registerLazySingleton<IdentityRepository>(
      () => IdentityRepositoryImpl(getIt<SupabaseIdentityDataSource>()),
    );
  } else {
    getIt.registerLazySingleton<IdentityRepository>(
      () => const IdentityRepositoryUnconfigured(),
    );
  }
  getIt.registerLazySingleton<BootstrapIdentityUseCase>(
    () => BootstrapIdentityUseCase(getIt<IdentityRepository>()),
  );
  getIt.registerFactory<IdentityBloc>(
    () => IdentityBloc(getIt<BootstrapIdentityUseCase>()),
  );

  if (isSupabaseReady) {
    getIt.registerLazySingleton<NearbyTransportService>(
      () => NearbyTransportService(
        supabaseClient: getIt<SupabaseClient>(),
        nativeDownloadSaver: getIt<NativeDownloadSaver>(),
      ),
    );
    getIt.registerLazySingleton<SupabaseTransferDataSource>(
      () => SupabaseTransferDataSource(
        supabaseClient: getIt<SupabaseClient>(),
        nativeDownloadSaver: getIt<NativeDownloadSaver>(),
        androidTransferService: getIt<AndroidTransferService>(),
        transferRecoveryScheduler: getIt<AndroidTransferRecoveryScheduler>(),
        storageBucket:
            dotenv.env['SUPABASE_STORAGE_BUCKET'] ??
            const String.fromEnvironment(
              'SUPABASE_STORAGE_BUCKET',
              defaultValue: 'transfers',
            ),
        supabaseUrl:
            dotenv.env['SUPABASE_URL'] ??
            const String.fromEnvironment('SUPABASE_URL'),
        supabaseKey:
            dotenv.env['SUPABASE_ANON_KEY'] ??
            const String.fromEnvironment('SUPABASE_ANON_KEY'),
        nearbyTransport: getIt<NearbyTransportService>(),
      ),
    );
    getIt.registerLazySingleton<TransferRepository>(
      () => TransferRepositoryImpl(
        dataSource: getIt<SupabaseTransferDataSource>(),
        picker: getIt<LocalFilePickerService>(),
        supabaseClient: getIt<SupabaseClient>(),
      ),
    );
  } else {
    getIt.registerLazySingleton<TransferRepository>(
      () => const TransferRepositoryUnconfigured(),
    );
  }
  getIt.registerLazySingleton<SendTransferUseCase>(
    () => SendTransferUseCase(getIt<TransferRepository>()),
  );
  getIt.registerLazySingleton<ObserveIncomingTransfersUseCase>(
    () => ObserveIncomingTransfersUseCase(getIt<TransferRepository>()),
  );
  getIt.registerFactory<SendTransferBloc>(
    () => SendTransferBloc(
      getIt<SendTransferUseCase>(),
      getIt<TransferRepository>(),
      getIt<AndroidIncomingNotificationService>(),
    ),
  );
  getIt.registerFactory<IncomingTransferBloc>(
    () => IncomingTransferBloc(
      getIt<ObserveIncomingTransfersUseCase>(),
      getIt<TransferRepository>(),
      getIt<AndroidIncomingNotificationService>(),
    ),
  );
}
