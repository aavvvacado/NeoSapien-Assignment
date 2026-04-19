// ignore_for_file: implementation_imports

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:crypto/src/digest_sink.dart';

/// Incremental SHA-256; call [close] before reading [hexDigest].
class StreamingSha256 {
  final DigestSink _digestSink = DigestSink();
  late final ByteConversionSink _sink =
      sha256.startChunkedConversion(_digestSink);

  void add(List<int> chunk) => _sink.add(chunk);

  void close() => _sink.close();

  String get hexDigest => _digestSink.value.toString();
}

class HashUtils {
  static const int _fileReadChunkBytes = 1024 * 1024;

  static Future<String> sha256OfFile(String path) async {
    final hasher = StreamingSha256();
    final raf = await File(path).open();
    try {
      while (true) {
        final chunk = await raf.read(_fileReadChunkBytes);
        if (chunk.isEmpty) break;
        hasher.add(chunk);
      }
    } finally {
      await raf.close();
    }
    hasher.close();
    return hasher.hexDigest;
  }
}
