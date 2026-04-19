import 'package:equatable/equatable.dart';

class PickedAttachmentMeta extends Equatable {
  const PickedAttachmentMeta({
    required this.name,
    required this.size,
    required this.path,
  });

  final String name;
  final int size;
  final String path;

  @override
  List<Object?> get props => [name, size, path];
}
