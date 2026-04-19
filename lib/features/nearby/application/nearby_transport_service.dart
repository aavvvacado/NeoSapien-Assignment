import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:neosapien_assignment/core/constants/app_constants.dart';
import 'package:neosapien_assignment/core/platform/android_multicast_lock.dart';
import 'package:neosapien_assignment/core/platform/native_download_saver.dart';
import 'package:neosapien_assignment/core/utils/hash_utils.dart';
import 'package:neosapien_assignment/features/transfer/domain/entities/transfer_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One file the sender streams over LAN after DB rows exist.
class NearbyLanFilePayload {
  const NearbyLanFilePayload({
    required this.fileId,
    required this.path,
    required this.name,
    required this.size,
    required this.sha256,
  });

  final String fileId;
  final String path;
  final String name;
  final int size;
  final String sha256;
}

/// LAN multicast discovery + direct TCP payload (Neo 1–style “nearby first”).
/// Wi‑Fi Direct / BLE can plug into the same coordinator later; v1 uses same-subnet multicast.
class NearbyTransportService {
  NearbyTransportService({
    required SupabaseClient supabaseClient,
    required NativeDownloadSaver nativeDownloadSaver,
    AndroidMulticastLock? multicastLock,
  }) : _supabase = supabaseClient,
       _nativeDownloadSaver = nativeDownloadSaver,
       _multicastLock = multicastLock ?? AndroidMulticastLock();

  final SupabaseClient _supabase;
  final NativeDownloadSaver _nativeDownloadSaver;
  final AndroidMulticastLock _multicastLock;

  InternetAddress get _mcGroup =>
      InternetAddress(AppConstants.nearbyMulticastAddress);

  ServerSocket? _server;
  RawDatagramSocket? _discoveryRx;
  StreamSubscription<RawSocketEvent>? _discoverySub;
  String? _advertisedUid;
  int? _advertisedTcpPort;

  /// Advertises this device on the LAN and accepts inbound P2P sessions (receiver role).
  Future<void> startHost(String myUid) async {
    if (_advertisedUid == myUid && _server != null) {
      return;
    }
    await stopHost();
    await _multicastLock.acquire();
    try {
      _server = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        0,
        shared: true,
      );
      _advertisedTcpPort = _server!.port;
      _advertisedUid = myUid;
      _discoveryRx = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        AppConstants.nearbyDiscoveryUdpPort,
        reuseAddress: true,
      );
      try {
        _discoveryRx!.joinMulticast(_mcGroup);
      } catch (_) {
        // Best-effort; some radios require explicit interface selection.
      }
      _discoverySub = _discoveryRx!.listen(_onDiscoveryEvent);
      unawaited(_acceptLoop());
    } catch (_) {
      await stopHost();
    }
  }

  void _onDiscoveryEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) {
      return;
    }
    final d = _discoveryRx?.receive();
    if (d == null) {
      return;
    }
    final uid = _advertisedUid;
    final port = _advertisedTcpPort;
    if (uid == null || port == null) {
      return;
    }
    final text = utf8.decode(d.data);
    if (!text.startsWith('NEOQ|v1|')) {
      return;
    }
    final parts = text.split('|');
    if (parts.length < 3) {
      return;
    }
    if (parts[2].trim() != uid) {
      return;
    }
    final reply = utf8.encode('NEOR|v1|$port');
    _discoveryRx!.send(reply, d.address, d.port);
  }

  Future<void> _acceptLoop() async {
    final server = _server;
    if (server == null) {
      return;
    }
    try {
      await for (final client in server) {
        unawaited(_handleInboundClient(client));
      }
    } catch (_) {
      // Server closed or network error.
    }
  }

  Future<void> _handleInboundClient(Socket socket) async {
    final myUid = _advertisedUid;
    if (myUid == null) {
      await socket.close();
      return;
    }
    final buf = _SocketSessionBuffer(socket);
    final touchedFileIds = <String>[];
    try {
      final helloLine = await buf.readLine();
      final hello = jsonDecode(helloLine) as Map<String, dynamic>;
      if (hello['t'] != 'hello') {
        throw StateError('bad_hello');
      }
      final transferId = hello['transferId'] as String?;
      final senderUid = hello['senderUid'] as String?;
      if (transferId == null || senderUid == null) {
        throw StateError('bad_hello_fields');
      }
      final rows = await _supabase
          .from('transfers')
          .select('id, sender_uid, receiver_uid')
          .eq('id', transferId)
          .limit(1);
      if (rows.isEmpty) {
        throw StateError('unknown_transfer');
      }
      final row = Map<String, dynamic>.from(rows.first as Map);
      if (row['receiver_uid'] != myUid || row['sender_uid'] != senderUid) {
        throw StateError('transfer_mismatch');
      }

      buf.writeLine(jsonEncode({'t': 'hello_ok'}));

      while (true) {
        final line = await buf.readLine();
        final hdr = jsonDecode(line) as Map<String, dynamic>;
        final t = hdr['t'] as String?;
        if (t == 'done') {
          break;
        }
        if (t != 'file') {
          throw StateError('bad_frame');
        }
        final fileId = hdr['id'] as String?;
        final name = hdr['name'] as String?;
        final size = hdr['size'] as int?;
        final sha = hdr['sha256'] as String?;
        if (fileId == null || name == null || size == null || sha == null) {
          throw StateError('bad_file_hdr');
        }
        if (size < 0 || size > AppConstants.maxTransferSizeBytes) {
          throw StateError('file_too_large');
        }

        final tmpDir = await getTemporaryDirectory();
        final safeName = p.basename(name);
        final outFile = File(
          p.join(tmpDir.path, 'neo_p2p_${fileId}_$safeName'),
        );
        final sink = outFile.openWrite();
        final hasher = StreamingSha256();
        try {
          await buf.drainBytesToSink(size, sink, hasher);
        } finally {
          await sink.close();
        }
        hasher.close();
        if (hasher.hexDigest != sha) {
          if (await outFile.exists()) {
            await outFile.delete();
          }
          throw StateError('hash_mismatch');
        }

        String? savedLocation;
        try {
          savedLocation = await _nativeDownloadSaver.saveFileToDeviceDownloads(
            fileName: name,
            sourcePath: outFile.path,
          );
          if (await outFile.exists()) {
            await outFile.delete();
          }
        } on UnsupportedError {
          // If on non-Android, keep in cache/tmp for now since we don't have desktop bridge
          savedLocation = outFile.path;
        }

        await _supabase
            .from('transfer_files')
            .update({
              'status': TransferFileStatus.completed.name,
              'bytes_transferred': size,
              'local_saved_path': savedLocation ?? outFile.path,
            })
            .eq('id', fileId);
        touchedFileIds.add(fileId);
        buf.writeLine(jsonEncode({'t': 'ack', 'id': fileId}));
      }

      buf.writeLine(jsonEncode({'t': 'session_ok'}));
    } catch (_) {
      await _rollbackIncomingFiles(touchedFileIds);
    } finally {
      await buf.close();
    }
  }

  Future<void> _rollbackIncomingFiles(List<String> fileIds) async {
    for (final id in fileIds) {
      try {
        final rows = await _supabase
            .from('transfer_files')
            .select('local_saved_path')
            .eq('id', id)
            .limit(1);
        if (rows.isNotEmpty) {
          final path = rows.first['local_saved_path'] as String?;
          if (path != null && path.isNotEmpty) {
            final f = File(path);
            if (await f.exists()) {
              await f.delete();
            }
          }
        }
        await _supabase
            .from('transfer_files')
            .update({
              'status': TransferFileStatus.uploading.name,
              'bytes_transferred': 0,
              'local_saved_path': null,
            })
            .eq('id', id);
      } catch (_) {
        // Best-effort rollback.
      }
    }
  }

  Future<void> stopHost() async {
    await _discoverySub?.cancel();
    _discoverySub = null;
    try {
      _discoveryRx?.close();
    } catch (_) {}
    _discoveryRx = null;
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
    _advertisedUid = null;
    _advertisedTcpPort = null;
    await _multicastLock.release();
  }

  /// Returns [true] if every file was written and acknowledged on the receiver.
  Future<bool> tryLanPeerTransferUpload({
    required String transferId,
    required String senderUid,
    required String receiverUid,
    required List<NearbyLanFilePayload> files,
  }) async {
    if (files.isEmpty) {
      return false;
    }
    final target = await _discoverReceiver(receiverUid);
    if (target == null) {
      return false;
    }
    Socket? socket;
    try {
      socket = await Socket.connect(
        target.host,
        target.port,
        timeout: const Duration(
          milliseconds: AppConstants.nearbyTcpConnectTimeoutMs,
        ),
      );
      final buf = _SocketSessionBuffer(socket);
      buf.writeLine(
        jsonEncode({
          't': 'hello',
          'transferId': transferId,
          'senderUid': senderUid,
        }),
      );
      final helloAck = jsonDecode(await buf.readLine()) as Map<String, dynamic>;
      if (helloAck['t'] != 'hello_ok') {
        return false;
      }

      for (final f in files) {
        buf.writeLine(
          jsonEncode({
            't': 'file',
            'id': f.fileId,
            'name': f.name,
            'size': f.size,
            'sha256': f.sha256,
          }),
        );
        final raf = await File(f.path).open();
        try {
          var left = f.size;
          while (left > 0) {
            final chunkSize = left > 262144 ? 262144 : left;
            final piece = await raf.read(chunkSize);
            if (piece.isEmpty) {
              throw StateError('short_read');
            }
            socket.add(piece);
            left -= piece.length;
          }
        } finally {
          await raf.close();
        }
        final ackLine = await buf.readLine();
        final ack = jsonDecode(ackLine) as Map<String, dynamic>;
        if (ack['t'] != 'ack' || ack['id'] != f.fileId) {
          return false;
        }
      }
      buf.writeLine(jsonEncode({'t': 'done'}));
      final doneAck = jsonDecode(await buf.readLine()) as Map<String, dynamic>;
      return doneAck['t'] == 'session_ok';
    } catch (_) {
      return false;
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  Future<({InternetAddress host, int port})?> _discoverReceiver(
    String receiverUid,
  ) async {
    RawDatagramSocket? socket;
    InternetAddress? host;
    var port = -1;
    final done = Completer<void>();
    StreamSubscription<RawSocketEvent>? sub;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sub = socket.listen((event) {
        if (event != RawSocketEvent.read) {
          return;
        }
        final d = socket!.receive();
        if (d == null) {
          return;
        }
        final text = utf8.decode(d.data);
        if (!text.startsWith('NEOR|v1|')) {
          return;
        }
        final parts = text.split('|');
        if (parts.length < 3) {
          return;
        }
        final p = int.tryParse(parts[2].trim());
        if (p == null) {
          return;
        }
        host = d.address;
        port = p;
        if (!done.isCompleted) {
          done.complete();
        }
      });
      final probe = utf8.encode('NEOQ|v1|$receiverUid');
      socket.send(probe, _mcGroup, AppConstants.nearbyDiscoveryUdpPort);
      try {
        await done.future.timeout(
          const Duration(milliseconds: AppConstants.nearbyDiscoveryTimeoutMs),
        );
      } on TimeoutException {
        // No peer answered on the LAN within the window.
      }
    } catch (_) {
      // ignore
    } finally {
      await sub?.cancel();
      socket?.close();
    }
    if (host == null || port < 0) {
      return null;
    }
    return (host: host!, port: port);
  }
}

class _SocketSessionBuffer {
  _SocketSessionBuffer(this._socket) {
    _subscription = _socket.listen(
      _onData,
      onError: (Object e, StackTrace st) {
        _error = e;
        _notifyWaiters();
      },
      onDone: () {
        _done = true;
        _notifyWaiters();
      },
      cancelOnError: true,
    );
  }

  final Socket _socket;
  final List<int> _buf = <int>[];
  bool _done = false;
  Object? _error;
  late final StreamSubscription<List<int>> _subscription;
  final List<Completer<void>> _waiters = <Completer<void>>[];

  void _onData(List<int> chunk) {
    _buf.addAll(chunk);
    _notifyWaiters();
  }

  void _notifyWaiters() {
    for (final w in _waiters) {
      if (!w.isCompleted) {
        w.complete();
      }
    }
    _waiters.clear();
  }

  Future<void> _waitWhile(bool Function() predicate) async {
    while (predicate()) {
      if (_error != null) {
        Error.throwWithStackTrace(_error!, StackTrace.current);
      }
      if (_done) {
        return;
      }
      final c = Completer<void>();
      _waiters.add(c);
      await c.future;
    }
  }

  Future<String> readLine() async {
    while (true) {
      await _waitWhile(() => !_buf.contains(0x0a) && !_done && _error == null);
      if (_error != null) {
        Error.throwWithStackTrace(_error!, StackTrace.current);
      }
      final ix = _buf.indexOf(0x0a);
      if (ix < 0) {
        if (_done) {
          throw StateError('peer_closed');
        }
        continue;
      }
      final raw = _buf.sublist(0, ix);
      _buf.removeRange(0, ix + 1);
      var end = raw.length;
      if (end > 0 && raw[end - 1] == 0x0d) {
        end--;
      }
      return utf8.decode(raw.sublist(0, end));
    }
  }

  Future<void> drainBytesToSink(
    int n,
    IOSink sink,
    StreamingSha256 hasher,
  ) async {
    var left = n;
    while (left > 0) {
      await _waitWhile(() => _buf.isEmpty && !_done && _error == null);
      if (_error != null) {
        Error.throwWithStackTrace(_error!, StackTrace.current);
      }
      if (_buf.isEmpty && _done) {
        throw StateError('peer_closed');
      }
      final take = left < _buf.length ? left : _buf.length;
      final chunk = Uint8List.fromList(_buf.sublist(0, take));
      _buf.removeRange(0, take);
      hasher.add(chunk);
      sink.add(chunk);
      left -= take;
    }
    await sink.flush();
  }

  void writeLine(String s) {
    _socket.add(utf8.encode('$s\n'));
  }

  Future<void> close() async {
    await _subscription.cancel();
    try {
      await _socket.close();
    } catch (_) {}
  }
}
