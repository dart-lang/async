// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Helper utilities for testing.
import "dart:async";

import "package:async/async.dart";
import "package:test/test.dart";

/// A zero-millisecond timer should wait until after all microtasks.
Future flushMicrotasks() => new Future.delayed(Duration.ZERO);

/// A generic unreachable callback function.
///
/// Returns a function that fails the test if it is ever called.
unreachable(String name) => ([a, b]) => fail("Unreachable: $name");

/// A badly behaved stream which throws if it's ever listened to.
///
/// Can be used to test cases where a stream should not be used.
class UnusableStream extends Stream {
  listen(onData, {onError, onDone, cancelOnError}) {
    throw new UnimplementedError("Gotcha!");
  }
}

/// A dummy [StreamSink] for testing the routing of the [done] and [close]
/// futures.
///
/// The [completer] field allows the user to control the future returned by
/// [done] and [close].
class CompleterStreamSink<T> implements StreamSink<T> {
  final completer = new Completer();

  Future get done => completer.future;

  void add(T event) {}
  void addError(error, [StackTrace stackTrace]) {}
  Future addStream(Stream<T> stream) async {}
  Future close() => completer.future;
}

/// A [StreamSink] that collects all events added to it as results.
///
/// This is used for testing code that interacts with sinks.
class TestSink<T> implements StreamSink<T> {
  /// The results corresponding to events that have been added to the sink.
  final results = <Result<T>>[];

  /// Whether [close] has been called.
  bool get isClosed => _isClosed;
  var _isClosed = false;

  Future get done => _doneCompleter.future;
  final _doneCompleter = new Completer();

  final Function _onDone;

  /// Creates a new sink.
  ///
  /// If [onDone] is passed, it's called when the user calls [close]. Its result
  /// is piped to the [done] future.
  TestSink({onDone()}) : _onDone = onDone ?? (() {});

  void add(T event) {
    results.add(new Result<T>.value(event));
  }

  void addError(error, [StackTrace stackTrace]) {
    results.add(new Result<T>.error(error, stackTrace));
  }

  Future addStream(Stream<T> stream) {
    var completer = new Completer.sync();
    stream.listen(add, onError: addError, onDone: completer.complete);
    return completer.future;
  }

  Future close() {
    _isClosed = true;
    _doneCompleter.complete(new Future.microtask(_onDone));
    return done;
  }
}
