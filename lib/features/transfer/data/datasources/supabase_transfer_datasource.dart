import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:neosapien_assignment/core/constants/app_constants.dart';
import 'package:neosapien_assignment/core/platform/android_transfer_recovery_scheduler.dart';
import 'package:neosapien_assignment/core/platform/android_transfer_service.dart';
import 'package:neosapien_assignment/core/platform/native_download_saver.dart';
import 'package:neosapien_assignment/core/utils/hash_utils.dart';
import 'package:neosapien_assignment/features/files/data/local_file_picker_service.dart';
import 'package:neosapien_assignment/features/nearby/application/nearby_transport_service.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/incoming_download_summary.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/transfer.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/transfer_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/logging/app_logger.dart';

class SupabaseTransferDataSource {
  SupabaseTransferDataSource({
    required SupabaseClient supabaseClient,
    required NativeDownloadSaver nativeDownloadSaver,
    required AndroidTransferService androidTransferService,
    required AndroidTransferRecoveryScheduler transferRecoveryScheduler,
    required String storageBucket,
    required String supabaseUrl,
    required String supabaseKey,
    NearbyTransportService? nearbyTransport,
  }) : _supabaseClient = supabaseClient,
       _nativeDownloadSaver = nativeDownloadSaver,
       _androidTransferService = androidTransferService,
       _transferRecoveryScheduler = transferRecoveryScheduler,
       _storageBucket = storageBucket,
       _supabaseUrl = supabaseUrl,
       _supabaseKey = supabaseKey,
       _nearbyTransport = nearbyTransport;

  final SupabaseClient _supabaseClient;
  final NativeDownloadSaver _nativeDownloadSaver;
  final AndroidTransferService _androidTransferService;
  final AndroidTransferRecoveryScheduler _transferRecoveryScheduler;
  final String _storageBucket;
  final String _supabaseUrl;
  final String _supabaseKey;
  final NearbyTransportService? _nearbyTransport;
  final Uuid _uuid = const Uuid();
  final _refreshTrigger = StreamController<void>.broadcast();
  static const int _downloadProgressFlushBytes = 2 * 1024 * 1024; // 2MB

  List<PickedLocalFile> selectedFiles = const [];
  String? activeTransferId;
  String? activeReceiverUid;
  String? activeSenderUid;

  Future<String> createTransfer({
    required String senderUid,
    required String recipientCode,
  }) async {
    final codeRows = await _supabaseClient
        .from('short_codes')
        .select('uid')
        .eq('code', recipientCode)
        .limit(1);
    if (codeRows.isEmpty || codeRows.first['uid'] == null) {
      throw StateError('invalid_recipient_code');
    }
    final receiverUid = codeRows.first['uid'] as String;
    if (receiverUid == senderUid) {
      throw StateError('self_send_not_allowed');
    }

    final transferId = _uuid.v4();
    final createdAt = DateTime.now();
    final ttl = createdAt.add(
      const Duration(hours: AppConstants.transferTtlHours),
    );
    activeTransferId = transferId;
    activeReceiverUid = receiverUid;
    activeSenderUid = senderUid;

    await _supabaseClient.from('transfers').insert({
      'id': transferId,
      'sender_uid': senderUid,
      'receiver_uid': receiverUid,
      'status': TransferStatus.initiated.name,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'ttl_expires_at': ttl.toUtc().toIso8601String(),
      'total_bytes': 0,
      'completed_bytes': 0,
    });

    _pokeRecipient(receiverUid, 'transfer_initiated');
    return transferId;
  }

  void _pokeRecipient(String receiverUid, String reason) {
    try {
      final channel = _supabaseClient.channel('pokes:$receiverUid');
      channel.subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          channel
              .sendBroadcastMessage(
                event: 'poke',
                payload: {
                  'reason': reason,
                  'at': DateTime.now().toUtc().toIso8601String(),
                },
              )
              .then((_) {
                AppLogger.info(
                  '[SupabaseTransferDataSource] Poke sent to $receiverUid: $reason',
                );
                _supabaseClient.removeChannel(channel);
              });
        }
      });
    } catch (e) {
      AppLogger.info(
        '[SupabaseTransferDataSource] Failed to poke recipient: $e',
      );
    }
  }

  Future<void> uploadFiles() async {
    final transferId = activeTransferId;
    if (transferId == null || selectedFiles.isEmpty) {
      throw StateError('missing_transfer_or_files');
    }

    // DO NOT update status to 'uploading' yet to avoid notifying the receiver with 0 files.
    // Instead, we just prepare everything and insert file records first.
    var completedBytes = 0;
    await _androidTransferService.start(
      title: 'NeoSapien Upload',
      message: 'Preparing ${selectedFiles.length} files',
    );
    try {
      final transferRows = await _supabaseClient
          .from('transfers')
          .select('id, status')
          .eq('id', transferId)
          .limit(1);
      if (transferRows.isEmpty ||
          transferRows.first['status'] == TransferStatus.cancelled.name ||
          transferRows.first['status'] == TransferStatus.failed.name) {
        throw StateError('transfer_aborted');
      }

      final existingFilesReq = await _supabaseClient
          .from('transfer_files')
          .select('id, name, sha256, storage_path, status')
          .eq('transfer_id', transferId);
      final hasExisting = existingFilesReq.isNotEmpty;
      final existingFilesRaw = existingFilesReq as List<dynamic>;

      final prepared = <({String fileId, PickedLocalFile file, String hash})>[];
      for (var i = 0; i < selectedFiles.length; i++) {
        final file = selectedFiles[i];
        await _androidTransferService.update(
          title: 'NeoSapien Upload',
          message: 'Preparing ${i + 1}/${selectedFiles.length}: ${file.name}',
        );

        String fileId;
        String hash;
        if (hasExisting && i < existingFilesRaw.length) {
          final row = existingFilesRaw[i];
          fileId = row['id'] as String;
          hash = row['sha256'] as String;
          // We don't need to re-insert
        } else {
          fileId = _uuid.v4();
          final safeName = p
              .basename(file.name)
              .replaceAll(RegExp(r'[^a-zA-Z0-9.\-]'), '_');
          final lanPath =
              '${AppConstants.lanOnlyStoragePathPrefix}${fileId}_$safeName';
          hash = await HashUtils.sha256OfFile(file.path);
          await _supabaseClient.from('transfer_files').insert({
            'id': fileId,
            'transfer_id': transferId,
            'name': file.name,
            'size': file.size,
            'sha256': hash,
            'storage_path': lanPath,
            'status': TransferFileStatus.uploading.name,
            'bytes_transferred': 0,
          });
        }
        prepared.add((fileId: fileId, file: file, hash: hash));
      }

      var usedLan = false;
      // NOW update the transfer status to 'uploading' after all files are in the DB.
      // This ensures the receiver's notification always has a correct file count.
      final totalBytes = selectedFiles.fold<int>(0, (acc, f) => acc + f.size);
      await _supabaseClient
          .from('transfers')
          .update({
            'status': TransferStatus.uploading.name,
            'total_bytes': totalBytes,
            'completed_bytes': 0,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', transferId);

      _pokeRecipient(activeReceiverUid!, 'upload_started');

      if (_nearbyTransport != null &&
          Platform.isAndroid &&
          activeSenderUid != null &&
          activeReceiverUid != null) {
        await _androidTransferService.update(
          title: 'NeoSapien Upload',
          message: 'Trying nearby Wi‑Fi…',
        );
        usedLan = await _nearbyTransport.tryLanPeerTransferUpload(
          transferId: transferId,
          senderUid: activeSenderUid!,
          receiverUid: activeReceiverUid!,
          files: prepared
              .map(
                (e) => NearbyLanFilePayload(
                  fileId: e.fileId,
                  path: e.file.path,
                  name: e.file.name,
                  size: e.file.size,
                  sha256: e.hash,
                ),
              )
              .toList(growable: false),
        );
      }

      if (usedLan) {
        completedBytes = totalBytes;
        await _androidTransferService.update(
          title: 'NeoSapien Upload',
          message: 'Sent via nearby Wi‑Fi',
        );
        await _supabaseClient
            .from('transfers')
            .update({
              'completed_bytes': completedBytes,
              'status': TransferStatus.uploaded.name,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', transferId);
        await _supabaseClient
            .from('transfers')
            .update({
              'status': TransferStatus.notifying.name,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', transferId);
        return;
      }

      var aggregateBytesSuccessfullyUploaded = 0;
      final failedFiles = <String>[];

      for (var i = 0; i < prepared.length; i++) {
        // PER-FILE ABORT CHECK
        final tStatus = await _supabaseClient
            .from('transfers')
            .select('status')
            .eq('id', transferId)
            .limit(1);
        if (tStatus.isNotEmpty &&
            (tStatus.first['status'] == TransferStatus.cancelled.name ||
                tStatus.first['status'] == TransferStatus.failed.name)) {
          throw StateError('transfer_aborted');
        }

        final row = prepared[i];
        final file = row.file;
        final fileId = row.fileId;
        final safeName = p
            .basename(file.name)
            .replaceAll(RegExp(r'[^a-zA-Z0-9.\-]'), '_');
        final storagePath = '$transferId/${fileId}_$safeName';

        // IMPLICIT RESUME CHECK
        final fStatus = await _supabaseClient
            .from('transfer_files')
            .select('status, bytes_transferred')
            .eq('id', fileId)
            .limit(1);
        if (fStatus.isNotEmpty &&
            fStatus.first['status'] == TransferFileStatus.completed.name) {
          aggregateBytesSuccessfullyUploaded += file.size;
          continue;
        }

        await _supabaseClient
            .from('transfer_files')
            .update({
              'storage_path': storagePath,
              'status': TransferFileStatus.uploading.name,
            })
            .eq('id', fileId);

        AppLogger.info(
          '[SupabaseTransferDataSource] Uploading ${file.name} (File ${i + 1}/${prepared.length})',
        );

        try {
          await _uploadWithProgress(
            file: File(file.path),
            storagePath: storagePath,
            onProgress: (bytesSent) async {
              final overallCompleted =
                  aggregateBytesSuccessfullyUploaded + bytesSent;

              // Only hit the DB every 2MB or at file completion to maintain speed
              if (bytesSent % (2 * 1024 * 1024) == 0 ||
                  bytesSent == file.size) {
                unawaited(
                  _supabaseClient
                      .from('transfer_files')
                      .update({'bytes_transferred': bytesSent})
                      .eq('id', fileId),
                );

                unawaited(
                  _supabaseClient
                      .from('transfers')
                      .update({'completed_bytes': overallCompleted})
                      .eq('id', transferId),
                );

                _pokeRecipient(activeReceiverUid!, 'upload_progress');
              }

              final fileProgress = bytesSent / file.size;
              await _androidTransferService.update(
                title: 'NeoSapien Upload',
                message:
                    'Uploading ${i + 1}/${prepared.length}: ${file.name} (${(fileProgress * 100).round()}%)',
              );
            },
          );

          aggregateBytesSuccessfullyUploaded += file.size;
          await _supabaseClient
              .from('transfer_files')
              .update({
                'status': TransferFileStatus.completed.name,
                'bytes_transferred': file.size,
              })
              .eq('id', fileId);
        } catch (e) {
          AppLogger.info(
            '[SupabaseTransferDataSource] Failed to upload ${file.name}: $e',
          );
          failedFiles.add(file.name);
          await _supabaseClient
              .from('transfer_files')
              .update({'status': TransferFileStatus.failed.name})
              .eq('id', fileId);
          // Continue with next file
        }

        await _supabaseClient
            .from('transfers')
            .update({'completed_bytes': aggregateBytesSuccessfullyUploaded})
            .eq('id', transferId);
      }

      final anySuccess = aggregateBytesSuccessfullyUploaded > 0;
      final finalStatus = failedFiles.isEmpty
          ? TransferStatus.uploaded
          : (anySuccess ? TransferStatus.uploaded : TransferStatus.failed);

      await _supabaseClient
          .from('transfers')
          .update({
            'status': finalStatus.name,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', transferId);

      if (failedFiles.isNotEmpty) {
        // Just notifying that it's "uploaded" (ready for receive) even if some failed
        await _supabaseClient
            .from('transfers')
            .update({
              'status': TransferStatus.notifying.name,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', transferId);
      } else {
        await _supabaseClient
            .from('transfers')
            .update({
              'status': TransferStatus.notifying.name,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', transferId);
      }

      await _supabaseClient
          .from('transfers')
          .update({
            'status': TransferStatus.uploaded.name,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', transferId);
      await _supabaseClient
          .from('transfers')
          .update({
            'status': TransferStatus.notifying.name,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', transferId);

      if (activeReceiverUid != null) {
        _pokeRecipient(activeReceiverUid!, 'upload_completed');
      }
    } catch (_) {
      await _transferRecoveryScheduler.enqueueRecovery(
        transferId: transferId,
        direction: 'upload',
      );
      if (activeReceiverUid != null) {
        _pokeRecipient(activeReceiverUid!, 'transfer_failed');
      }
      rethrow;
    } finally {
      await _androidTransferService.stop();
    }
  }

  Stream<List<Transfer>> observeIncoming(String receiverUid) {
    final controller = StreamController<List<Transfer>>();
    final channel = _supabaseClient.channel('incoming-transfers-$receiverUid');

    Future<void> emitSnapshot() async {
      final rows = await _supabaseClient
          .from('transfers')
          .select()
          .eq('receiver_uid', receiverUid)
          .order('created_at', ascending: false);
      final transferIds = rows
          .map((row) => row['id'] as String)
          .toList(growable: false);
      final filesByTransfer = await _loadFilesGrouped(transferIds);
      controller.add(
        rows
            .map(
              (row) => _mapTransferRow(
                row,
                filesByTransfer[row['id'] as String] ?? const [],
              ),
            )
            .toList(growable: false),
      );
    }

    void runSnapshot() {
      if (controller.isClosed) return;
      AppLogger.info(
        '[SupabaseTransferDataSource] Running snapshot for receiver: $receiverUid',
      );
      emitSnapshot().catchError((Object e, StackTrace st) {
        AppLogger.info('[SupabaseTransferDataSource] Snapshot error: $e');
        if (!controller.isClosed) {
          controller.addError(e, st);
        }
      });
    }

    runSnapshot();

    final refreshSub = _refreshTrigger.stream.listen((_) => runSnapshot());

    final pokeChannel = _supabaseClient.channel('pokes:$receiverUid');
    pokeChannel
        .onBroadcast(
          event: 'poke',
          callback: (payload) {
            AppLogger.info(
              '[SupabaseTransferDataSource] Received Broadcast Poke: ${payload['reason']}',
            );
            runSnapshot();
          },
        )
        .subscribe((status, [error]) {
          AppLogger.info(
            '[SupabaseTransferDataSource] Poke channel status ($receiverUid): $status',
          );
        });

    channel
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'transfers',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'receiver_uid',
          value: receiverUid,
        ),
        callback: (payload) {
          print(
            '[SupabaseTransferDataSource] Postgres Change (transfers): ${payload.eventType}',
          );
          runSnapshot();
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'transfer_files',
        callback: (payload) {
          // Optimization: Check if this file belongs to one of our active incoming transfers
          // For now, just trigger refresh as it was doing.
          print(
            '[SupabaseTransferDataSource] Postgres Change (transfer_files): ${payload.eventType}',
          );
          runSnapshot();
        },
      )
      ..subscribe((status, [error]) {
        print(
          '[SupabaseTransferDataSource] Postgres channel status ($receiverUid): $status',
        );
        if (error != null) {
          print(
            '[SupabaseTransferDataSource] Postgres subscription error: $error',
          );
        }
      });

    controller.onCancel = () {
      print(
        '[SupabaseTransferDataSource] Closing channels for receiver: $receiverUid',
      );
      _supabaseClient.removeChannel(channel);
      _supabaseClient.removeChannel(pokeChannel);
      refreshSub.cancel();
    };

    return controller.stream;
  }

  Stream<Transfer?> observeTransferById(String transferId) {
    final controller = StreamController<Transfer?>();
    final channel = _supabaseClient.channel('transfer-$transferId');

    Future<void> emitSnapshot() async {
      final rows = await _supabaseClient
          .from('transfers')
          .select()
          .eq('id', transferId)
          .limit(1);
      if (rows.isEmpty) {
        controller.add(null);
        return;
      }
      final filesByTransfer = await _loadFilesGrouped([transferId]);
      controller.add(
        _mapTransferRow(rows.first, filesByTransfer[transferId] ?? const []),
      );
    }

    void runSnapshot() {
      emitSnapshot().catchError((Object e, StackTrace st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
        }
      });
    }

    runSnapshot();

    channel
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'transfers',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: transferId,
        ),
        callback: (_) => runSnapshot(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'transfer_files',
        callback: (_) => runSnapshot(),
      )
      ..subscribe();

    controller.onCancel = () {
      _supabaseClient.removeChannel(channel);
    };

    return controller.stream;
  }

  Future<Transfer?> fetchTransferById(String transferId) async {
    final rows = await _supabaseClient
        .from('transfers')
        .select()
        .eq('id', transferId)
        .limit(1);
    if (rows.isEmpty) {
      return null;
    }
    final id = rows.first['id'] as String;
    final filesByTransfer = await _loadFilesGrouped([id]);
    return _mapTransferRow(rows.first, filesByTransfer[id] ?? const []);
  }

  Future<void> cancelTransfer(String transferId) async {
    await _supabaseClient
        .from('transfers')
        .update({
          'status': TransferStatus.cancelled.name,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', transferId);

    // Poke the other side about the cancellation
    final transfer = await fetchTransferById(transferId);
    if (transfer != null) {
      final peerUid = (activeSenderUid == transfer.senderUid)
          ? transfer.receiverUid
          : transfer.senderUid;
      _pokeRecipient(peerUid, 'transfer_cancelled');
    }
  }

  Future<void> _publishDownloadProgress({
    required String transferId,
    required String fileId,
    required int fileSize,
    required int receivedBytes,
    required int priorCompletedBytes,
    required String? senderUid,
    bool isHighFrequency = false,
  }) async {
    final clamped = receivedBytes.clamp(0, fileSize);

    // Only hit the DB for progress if it's NOT a high-frequency UI tick,
    // or if the file is finished.
    if (!isHighFrequency || clamped >= fileSize) {
      unawaited(
        _supabaseClient
            .from('transfer_files')
            .update({
              'status': TransferFileStatus.downloading.name,
              'bytes_transferred': clamped,
            })
            .eq('id', fileId),
      );
      unawaited(
        _supabaseClient
            .from('transfers')
            .update({
              'completed_bytes': priorCompletedBytes + clamped,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', transferId),
      );
    }

    // Notify the SENDER that progress has been made
    if (senderUid != null) {
      _pokeRecipient(senderUid, 'download_progress');
    }
  }

  Future<({String sha256Hex, int bytesReceived})>
  _downloadFileViaSignedUrlWithProgress({
    required String storagePath,
    required String transferId,
    required String fileId,
    required int fileSize,
    required int priorCompletedBytes,
    required int totalTransferBytes,
    required String fileName,
    required int fileIndex,
    required int fileCount,
    required File outputFile,
    required String? senderUid,
  }) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount <= maxRetries) {
      final signedUrl = await _supabaseClient.storage
          .from(_storageBucket)
          .createSignedUrl(storagePath, 3600);
      final client = http.Client();
      try {
        final response = await client.send(
          http.Request('GET', Uri.parse(signedUrl)),
        );
        if (response.statusCode != 200) {
          throw StateError('download_http_${response.statusCode}');
        }
        final sink = outputFile.openWrite();
        final hasher = StreamingSha256();
        var received = 0;
        var lastFlushBytes = 0;
        var lastFgUpdate = DateTime.fromMillisecondsSinceEpoch(0);
        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
            hasher.add(chunk);
            received += chunk.length;
            final now = DateTime.now();
            final dueSize = received >= fileSize && fileSize > 0;
            final dueChunk =
                received - lastFlushBytes >= _downloadProgressFlushBytes;
            final dueTime = now.difference(lastFgUpdate).inMilliseconds >= 400;
            if (dueSize || dueChunk || dueTime) {
              lastFlushBytes = received;
              lastFgUpdate = now;
              final clamped = fileSize > 0
                  ? received.clamp(0, fileSize)
                  : received;
              unawaited(
                _publishDownloadProgress(
                  transferId: transferId,
                  fileId: fileId,
                  fileSize: fileSize,
                  receivedBytes: clamped,
                  priorCompletedBytes: priorCompletedBytes,
                  senderUid: senderUid,
                  isHighFrequency:
                      dueTime &&
                      !dueSize, // Flag to skip DB sync if just a time tick
                ),
              );
              final denom = totalTransferBytes > 0
                  ? totalTransferBytes
                  : fileSize;
              if (denom > 0) {
                final overall = ((priorCompletedBytes + clamped) / denom).clamp(
                  0.0,
                  1.0,
                );
                await _androidTransferService.update(
                  title: 'NeoSapien Download',
                  message:
                      'File ${fileIndex + 1}/$fileCount · ${(overall * 100).round()}% · $fileName',
                );
              } else {
                await _androidTransferService.update(
                  title: 'NeoSapien Download',
                  message: 'File ${fileIndex + 1}/$fileCount · $fileName',
                );
              }
            }
          }
        } finally {
          await sink.close();
        }
        final finalReceived = fileSize > 0
            ? received.clamp(0, fileSize)
            : received;
        await _publishDownloadProgress(
          transferId: transferId,
          fileId: fileId,
          fileSize: fileSize,
          receivedBytes: finalReceived,
          priorCompletedBytes: priorCompletedBytes,
          senderUid: senderUid,
        );
        hasher.close();
        return (sha256Hex: hasher.hexDigest, bytesReceived: received);
      } catch (e) {
        retryCount++;
        unawaited(
          _androidTransferService.update(
            title: 'NeoSapien Download',
            message: 'Connection lost. Reconnecting (Attempt $retryCount/3)...',
          ),
        );
        AppLogger.info(
          '[SupabaseTransferDataSource] Download attempt $retryCount failed ($e). Retrying in ${4 * retryCount}s for carrier handoff...',
        );
        if (retryCount > maxRetries) {
          if (await outputFile.exists()) {
            try {
              await outputFile.delete();
            } catch (_) {}
          }
          rethrow;
        }
        await Future.delayed(Duration(seconds: 4 * retryCount));
      } finally {
        client.close();
      }
    }
    throw StateError('download_failed_after_retries');
  }

  Future<IncomingDownloadSummary> downloadIncomingTransfer(
    String transferId,
  ) async {
    final files = await _supabaseClient
        .from('transfer_files')
        .select('id, status, size, local_saved_path')
        .eq('transfer_id', transferId);
    var alreadyCompletedBytes = 0;
    for (final file in files) {
      // Sender marks rows `completed` after upload to Storage. That is NOT "saved on this phone".
      // Only treat as done-for-resume when we already persisted a local path for the receiver.
      final savedHere = _hasNonEmptyLocalPath(file['local_saved_path'] as String?);
      final serverUploadComplete =
          file['status'] == TransferFileStatus.completed.name;
      if (serverUploadComplete && savedHere) {
        alreadyCompletedBytes += (file['size'] as int?) ?? 0;
      } else {
        await _supabaseClient
            .from('transfer_files')
            .update({
              'status': TransferFileStatus.downloading.name,
              'bytes_transferred': 0,
            })
            .eq('id', file['id'] as String);
      }
    }
    await _supabaseClient
        .from('transfers')
        .update({
          'status': TransferStatus.downloading.name,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'completed_bytes': alreadyCompletedBytes,
        })
        .eq('id', transferId);

    // Get sender_uid to poke them
    final transferRows = await _supabaseClient
        .from('transfers')
        .select('total_bytes, sender_uid')
        .eq('id', transferId)
        .limit(1);
    if (transferRows.isEmpty) {
      throw StateError('transfer_not_found');
    }
    final senderUid = transferRows.first['sender_uid'] as String?;
    if (senderUid != null) {
      _pokeRecipient(senderUid, 'download_started');
    }

    final transferFiles = await _supabaseClient
        .from('transfer_files')
        .select(
          'id, name, storage_path, size, sha256, local_saved_path, status',
        )
        .eq('transfer_id', transferId);

    final requiredBytes = transferFiles.fold<int>(
      0,
      (sum, row) => sum + ((row['size'] as int?) ?? 0),
    );
    final availableBytes = await _nativeDownloadSaver
        .getAvailableDownloadBytes();
    if (availableBytes != null && requiredBytes > availableBytes) {
      await _supabaseClient
          .from('transfers')
          .update({
            'status': TransferStatus.failed.name,
            'failure_code': 'low_storage',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', transferId);
      throw StateError(
        'Not enough device storage. Need ${(requiredBytes / (1024 * 1024)).toStringAsFixed(1)} MB free.',
      );
    }

    final baseDir = await getApplicationDocumentsDirectory();
    var priorFilesCompletedSum = 0;
    final savedRefs = <SavedDownloadRef>[];
    await _androidTransferService.start(
      title: 'NeoSapien Download',
      message: 'Preparing ${transferFiles.length} files',
    );
    try {
      for (var i = 0; i < transferFiles.length; i++) {
        // PER-FILE ABORT CHECK
        final tStatus = await _supabaseClient
            .from('transfers')
            .select('status')
            .eq('id', transferId)
            .limit(1);
        if (tStatus.isNotEmpty &&
            (tStatus.first['status'] == TransferStatus.cancelled.name ||
                tStatus.first['status'] == TransferStatus.failed.name)) {
          throw StateError('transfer_aborted');
        }

        final row = transferFiles[i];
        final fileId = row['id'] as String;
        final fileName = row['name'] as String;
        final storagePath = row['storage_path'] as String;
        final expectedHash = row['sha256'] as String? ?? '';
        final fileSize = (row['size'] as int?) ?? 0;
        await _androidTransferService.update(
          title: 'NeoSapien Download',
          message: 'Starting ${i + 1}/${transferFiles.length}: $fileName',
        );
        final localSavedPath = row['local_saved_path'] as String?;
        final isLanPlaceholder = storagePath.startsWith(
          AppConstants.lanOnlyStoragePathPrefix,
        );

        // IMPLICIT RESUME: only skip when this device already saved the file (has local path).
        // `completed` alone also means "sender finished uploading" — must not skip receive.
        if (row['status'] == TransferFileStatus.completed.name &&
            _hasNonEmptyLocalPath(row['local_saved_path'] as String?)) {
          priorFilesCompletedSum += fileSize;
          savedRefs.add(
            SavedDownloadRef(
              fileName: fileName,
              openUriOrPath: (row['local_saved_path'] as String).trim(),
            ),
          );
          continue;
        }

        late final String actualHash;
        late final int bytesReceived;
        late final String savedLocation;

        if (isLanPlaceholder &&
            localSavedPath != null &&
            localSavedPath.isNotEmpty) {
          final src = File(localSavedPath);
          if (!await src.exists()) {
            throw StateError('lan_delivery_not_available');
          }
          final hasher = StreamingSha256();
          await for (final chunk in src.openRead()) {
            hasher.add(chunk);
          }
          hasher.close();
          actualHash = hasher.hexDigest;
          bytesReceived = fileSize;
          if (expectedHash.isNotEmpty && actualHash != expectedHash) {
            await _supabaseClient
                .from('transfer_files')
                .update({'status': TransferFileStatus.failed.name})
                .eq('id', fileId);
            await _supabaseClient
                .from('transfers')
                .update({
                  'status': TransferStatus.failed.name,
                  'failure_code': 'hash_mismatch',
                  'updated_at': DateTime.now().toUtc().toIso8601String(),
                })
                .eq('id', transferId);
            throw StateError('Downloaded file integrity check failed');
          }
          try {
            savedLocation = await _nativeDownloadSaver
                .saveFileToDeviceDownloads(
                  fileName: fileName,
                  sourcePath: src.path,
                );
          } on UnsupportedError {
            final outFile = await _resolveUniqueOutputFile(
              baseDir.path,
              fileName,
            );
            await src.copy(outFile.path);
            savedLocation = outFile.path;
          }
          if (src.path != savedLocation) {
            try {
              await src.delete();
            } catch (_) {}
          }
        } else if (isLanPlaceholder) {
          throw StateError('lan_delivery_not_available');
        } else {
          final workingFile = await _resolveUniqueOutputFile(
            baseDir.path,
            fileName,
          );
          final downloaded = await _downloadFileViaSignedUrlWithProgress(
            storagePath: storagePath,
            transferId: transferId,
            fileId: fileId,
            fileSize: fileSize,
            priorCompletedBytes: priorFilesCompletedSum,
            totalTransferBytes: requiredBytes,
            fileName: fileName,
            fileIndex: i,
            fileCount: transferFiles.length,
            outputFile: workingFile,
            senderUid: senderUid,
          );
          actualHash = downloaded.sha256Hex;
          bytesReceived = downloaded.bytesReceived;
          if (expectedHash.isNotEmpty && actualHash != expectedHash) {
            if (await workingFile.exists()) {
              await workingFile.delete();
            }
            await _supabaseClient
                .from('transfer_files')
                .update({'status': TransferFileStatus.failed.name})
                .eq('id', fileId);
            await _supabaseClient
                .from('transfers')
                .update({
                  'status': TransferStatus.failed.name,
                  'failure_code': 'hash_mismatch',
                  'updated_at': DateTime.now().toUtc().toIso8601String(),
                })
                .eq('id', transferId);
            throw StateError('Downloaded file integrity check failed');
          }
          try {
            savedLocation = await _nativeDownloadSaver
                .saveFileToDeviceDownloads(
                  fileName: fileName,
                  sourcePath: workingFile.path,
                );
            if (await workingFile.exists()) {
              await workingFile.delete();
            }
          } on UnsupportedError {
            final outFile = await _resolveUniqueOutputFile(
              baseDir.path,
              fileName,
            );
            try {
              await workingFile.rename(outFile.path);
            } on FileSystemException {
              await workingFile.copy(outFile.path);
              if (await workingFile.exists()) {
                await workingFile.delete();
              }
            }
            savedLocation = outFile.path;
          }
        }
        priorFilesCompletedSum += bytesReceived;
        await _updateTransferFileCompleted(
          fileId: fileId,
          bytesTransferred: bytesReceived,
          localSavedPath: savedLocation,
        );
        await _supabaseClient
            .from('transfers')
            .update({
              'completed_bytes': priorFilesCompletedSum,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', transferId);
        savedRefs.add(
          SavedDownloadRef(fileName: fileName, openUriOrPath: savedLocation),
        );
      }

      await _supabaseClient
          .from('transfers')
          .update({
            'status': TransferStatus.completed.name,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', transferId);
      return IncomingDownloadSummary(saved: savedRefs);
    } catch (_) {
      await _transferRecoveryScheduler.enqueueRecovery(
        transferId: transferId,
        direction: 'download',
      );
      if (senderUid != null) {
        _pokeRecipient(senderUid, 'transfer_failed');
      }
      rethrow;
    } finally {
      await _androidTransferService.stop();
    }
  }

  Future<void> fetchIncomingTransfersFor(String uid) async {
    _refreshTrigger.add(null);
  }

  Future<File> _resolveUniqueOutputFile(
    String basePath,
    String fileName,
  ) async {
    final ext = p.extension(fileName);
    final stem = ext.isEmpty
        ? fileName
        : fileName.substring(0, fileName.length - ext.length);
    var candidate = File(p.join(basePath, fileName));
    var index = 1;
    while (await candidate.exists()) {
      candidate = File(p.join(basePath, '${stem}_$index$ext'));
      index++;
    }
    return candidate;
  }

  Future<void> _updateTransferFileCompleted({
    required String fileId,
    required int bytesTransferred,
    required String localSavedPath,
  }) async {
    final payload = {
      'status': TransferFileStatus.completed.name,
      'bytes_transferred': bytesTransferred,
      'local_saved_path': localSavedPath,
    };
    try {
      await _supabaseClient
          .from('transfer_files')
          .update(payload)
          .eq('id', fileId);
      print('[SupabaseTransferDataSource] File completed: $fileId');
      // No explicit poke here as the parent transfer update will trigger it
    } on PostgrestException catch (e) {
      // Do not silently drop local_saved_path: the UI needs it to open/share files.
      if (e.code == 'PGRST204' || e.message.contains('local_saved_path')) {
        throw StateError(
          'Database missing transfer_files.local_saved_path. Run '
          '`alter table public.transfer_files add column if not exists local_saved_path text null;` '
          'from docs/supabase_setup.sql, then retry Receive.',
        );
      }
      rethrow;
    }
  }

  Future<Map<String, List<TransferFile>>> _loadFilesGrouped(
    List<String> transferIds,
  ) async {
    if (transferIds.isEmpty) {
      return const {};
    }
    final rows = await _supabaseClient
        .from('transfer_files')
        .select()
        .inFilter('transfer_id', transferIds);
    final map = <String, List<TransferFile>>{};
    for (final row in rows) {
      final transferId = row['transfer_id'] as String;
      map.putIfAbsent(transferId, () => []);
      map[transferId]!.add(
        TransferFile(
          fileId: row['id'] as String,
          name: row['name'] as String,
          size: row['size'] as int? ?? 0,
          sha256: row['sha256'] as String? ?? '',
          storagePath: row['storage_path'] as String? ?? '',
          progress: (row['size'] as int? ?? 0) == 0
              ? 0
              : ((row['bytes_transferred'] as int? ?? 0) /
                    (row['size'] as int)),
          status: TransferFileStatus.values.firstWhere(
            (item) =>
                item.name ==
                (row['status'] as String? ?? TransferFileStatus.pending.name),
            orElse: () => TransferFileStatus.pending,
          ),
          localSavedPath: row['local_saved_path'] as String?,
        ),
      );
    }
    return map;
  }

  Transfer _mapTransferRow(
    Map<String, dynamic> data,
    List<TransferFile> files,
  ) {
    final persistedStatus =
        data['status'] as String? ?? TransferStatus.initiated.name;
    final ttlRaw = data['ttl_expires_at'] as String?;
    final ttl = DateTime.tryParse(ttlRaw ?? '') ?? DateTime.now();
    // Past TTL means the transfer is no longer actionable, but do not mask terminal outcomes.
    final ttlTerminalStatuses = <String>{
      TransferStatus.completed.name,
      TransferStatus.failed.name,
      TransferStatus.cancelled.name,
      TransferStatus.expired.name,
    };
    final isExpired =
        DateTime.now().isAfter(ttl) &&
        !ttlTerminalStatuses.contains(persistedStatus);

    return Transfer(
      transferId: data['id'] as String? ?? '',
      senderUid: data['sender_uid'] as String? ?? '',
      receiverUid: data['receiver_uid'] as String? ?? '',
      status: TransferStatus.values.firstWhere(
        (item) =>
            item.name ==
            (isExpired ? TransferStatus.expired.name : persistedStatus),
        orElse: () => TransferStatus.initiated,
      ),
      files: files,
      createdAt:
          DateTime.tryParse(data['created_at'] as String? ?? '') ??
          DateTime.now(),
      ttlExpiresAt: ttl,
      totalBytes: data['total_bytes'] as int? ?? 0,
      completedBytes: data['completed_bytes'] as int? ?? 0,
      failureCode: data['failure_code'] as String?,
    );
  }

  /// Receiver-side: `local_saved_path` is set only after MediaStore / disk save on this device.
  bool _hasNonEmptyLocalPath(String? path) {
    if (path == null) return false;
    return path.trim().isNotEmpty;
  }

  Future<void> _uploadWithProgress({
    required File file,
    required String storagePath,
    required Future<void> Function(int bytesSent) onProgress,
  }) async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount <= maxRetries) {
      try {
        await _performUpload(file, storagePath, onProgress);
        return; // Success
      } catch (e) {
        retryCount++;
        unawaited(
          _androidTransferService.update(
            title: 'NeoSapien Upload',
            message: 'Connection lost. Reconnecting (Attempt $retryCount/3)...',
          ),
        );
        AppLogger.info(
          '[SupabaseTransferDataSource] Upload attempt $retryCount failed ($e). Retrying in ${4 * retryCount}s for carrier handoff...',
        );
        if (retryCount > maxRetries) rethrow;
        await Future.delayed(
          Duration(seconds: 4 * retryCount),
        ); // Slower backoff for LTE/Wi-Fi switching
      }
    }
  }

  Future<void> _performUpload(
    File file,
    String storagePath,
    Future<void> Function(int bytesSent) onProgress,
  ) async {
    final session = _supabaseClient.auth.currentSession;
    if (session == null) throw StateError('no_session');

    final url = Uri.parse(
      '$_supabaseUrl/storage/v1/object/$_storageBucket/$storagePath',
    );
    final request = http.StreamedRequest('POST', url);
    request.headers.addAll({
      'Authorization': 'Bearer ${session.accessToken}',
      'apiKey': _supabaseKey,
      'Content-Type': 'application/octet-stream',
      'x-upsert': 'true', // Allow overwriting for retries
    });

    final fileStream = file.openRead();
    var bytesSent = 0;

    final subscription = fileStream.listen(
      (chunk) {
        request.sink.add(chunk);
        bytesSent += chunk.length;
        onProgress(bytesSent).catchError((e) {
          print('[SupabaseTransferDataSource] Progress update error: $e');
        });
      },
      onDone: () {
        request.sink.close();
      },
      onError: (e) {
        request.sink.addError(e);
      },
      cancelOnError: true,
    );

    try {
      final response = await http.Response.fromStream(await request.send());
      if (response.statusCode != 200) {
        throw StateError(
          'upload_failed_http_${response.statusCode}: ${response.body}',
        );
      }
    } finally {
      await subscription.cancel();
    }
  }
}
