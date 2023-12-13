import 'error.dart';
import 'result.dart';

/// [CaptureExtension] is an extension to capture any error into
/// the [Result.capture] property allowing inline catching
extension CaptureExtension<T> on Future<T> {
  /// Captures the result of a future into a `Result` future.
  ///
  /// The resulting future will never have an error.
  /// Errors have been converted to an [ErrorResult] value.
  ///
  Future<Result<T>> capture() => Result.capture(this);
}
