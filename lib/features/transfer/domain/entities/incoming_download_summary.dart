import 'package:equatable/equatable.dart';

class SavedDownloadRef extends Equatable {
  const SavedDownloadRef({
    required this.fileName,
    required this.openUriOrPath,
  });

  final String fileName;
  final String openUriOrPath;

  @override
  List<Object?> get props => [fileName, openUriOrPath];
}

class IncomingDownloadSummary extends Equatable {
  const IncomingDownloadSummary({required this.saved});

  final List<SavedDownloadRef> saved;

  SavedDownloadRef? get primaryIfAny => saved.isEmpty ? null : saved.first;

  @override
  List<Object?> get props => [saved];
}
