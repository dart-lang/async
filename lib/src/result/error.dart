// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'result.dart';
import 'value.dart';

/// A result representing a thrown error.
class ErrorResult implements Result<Null> {
  /// The error object that was thrown.
  final error;

  /// The stack trace corresponding to where [error] was thrown.
  final StackTrace stackTrace;

  bool get isValue => false;
  bool get isError => true;
  ValueResult<Null> get asValue => null;
  ErrorResult get asError => this;

  ErrorResult(this.error, this.stackTrace);

  void complete(Completer completer) {
    completer.completeError(error, stackTrace);
  }

  void addTo(EventSink sink) {
    sink.addError(error, stackTrace);
  }

  Future<Null> get asFuture => new Future<Null>.error(error, stackTrace);

  /// Calls an error handler with the error and stacktrace.
  ///
  /// An async error handler function is either a function expecting two
  /// arguments, which will be called with the error and the stack trace, or it
  /// has to be a function expecting only one argument, which will be called
  /// with only the error.
  void handle(Function errorHandler) {
    if (errorHandler is ZoneBinaryCallback) {
      errorHandler(error, stackTrace);
    } else {
      errorHandler(error);
    }
  }

  int get hashCode => error.hashCode ^ stackTrace.hashCode ^ 0x1d61823f;

  /// This is equal only to an error result with equal [error] and [stackTrace].
  bool operator ==(Object other) =>
      other is ErrorResult &&
      error == other.error &&
      stackTrace == other.stackTrace;
}
