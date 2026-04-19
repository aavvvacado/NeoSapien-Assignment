import 'package:neosapien_assignment/core/error/failure.dart';

class Result<T> {
  const Result._({this.value, this.failure});

  final T? value;
  final Failure? failure;

  bool get isSuccess => value != null && failure == null;
  bool get isFailure => failure != null;

  static Result<T> success<T>(T value) => Result<T>._(value: value);
  static Result<T> fail<T>(Failure failure) => Result<T>._(failure: failure);
}
