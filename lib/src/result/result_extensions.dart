import 'result.dart';

extension ResultExtensions<T> on Result<T> {
  /// Returns the value if the result [isValue].
  ///
  /// If the result [isError], it throws the corresponding error and stacktrace.
  T get requireValue {
    if (isValue) return asValue!.value;
    Error.throwWithStackTrace(asError!.error, asError!.stackTrace);
  }

  /// Returns the value if the result [isValue].
  ///
  /// Returns null otherwise
  T? get valueOrNull => asValue?.value;
}
