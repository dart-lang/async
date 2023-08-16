// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'condition.dart';

/// Utility extensions on [Stream].
extension StreamExtensions<T> on Stream<T> {
  /// Creates a stream whose elements are contiguous slices of `this`.
  ///
  /// Each slice is [length] elements long, except for the last one which may be
  /// shorter if `this` emits too few elements. Each slice begins after the
  /// last one ends.
  ///
  /// For example, `Stream.fromIterable([1, 2, 3, 4, 5]).slices(2)` emits
  /// `([1, 2], [3, 4], [5])`.
  ///
  /// Errors are forwarded to the result stream immediately when they occur,
  /// even if previous data events have not been emitted because the next slice
  /// is not complete yet.
  Stream<List<T>> slices(int length) {
    if (length < 1) throw RangeError.range(length, 1, null, 'length');

    var slice = <T>[];
    return transform(StreamTransformer.fromHandlers(handleData: (data, sink) {
      slice.add(data);
      if (slice.length == length) {
        sink.add(slice);
        slice = [];
      }
    }, handleDone: (sink) {
      if (slice.isNotEmpty) sink.add(slice);
      sink.close();
    }));
  }

  /// A future which completes with the first event of this stream, or with
  /// `null`.
  ///
  /// This stream is listened to, and if it emits any event, whether a data
  /// event or an error event, the future completes with the same data value or
  /// error. If the stream ends without emitting any events, the future is
  /// completed with `null`.
  Future<T?> get firstOrNull {
    var completer = Completer<T?>.sync();
    final subscription = listen(null,
        onError: completer.completeError,
        onDone: completer.complete,
        cancelOnError: true);
    subscription.onData((event) {
      subscription.cancel().whenComplete(() {
        completer.complete(event);
      });
    });
    return completer.future;
  }

  /// Eagerly listens to this stream and buffers events until needed.
  ///
  /// The returned stream will emit the same events as this stream, starting
  /// from when this method is called. The events are delayed until the returned
  /// stream is listened to, at which point all buffered events will be emitted
  /// in order, and then further events from this stream will be emitted as they
  /// arrive.
  ///
  /// The buffer will retain all events until the returned stream is listened
  /// to, so if the stream can emit arbitrary amounts of data, callers should be
  /// careful to listen to the stream eventually or call
  /// `stream.listen(null).cancel()` to discard the buffered data if it becomes
  /// clear that the data isn't not needed.
  Stream<T> listenAndBuffer() {
    var controller = StreamController<T>(sync: true);
    var subscription = listen(controller.add,
        onError: controller.addError, onDone: controller.close);
    controller
      ..onPause = subscription.pause
      ..onResume = subscription.resume
      ..onCancel = subscription.cancel;
    return controller.stream;
  }

  /// Invoke [each] for each item in this stream, and wait for the [Future]
  /// returned by [each] to be resolved. Running no more than [concurrency]
  /// number of [each] calls at the same time.
  ///
  /// This function will wait for the futures returned by [each] to be resolved
  /// before completing. If any [each] invocation throws, [boundedForEach] will
  /// continue subsequent [each] calls, ignore additional errors and throw the
  /// first error encountered.
  Future<void> boundedForEach(
    int concurrency,
    FutureOr<void> Function(T item) each,
  ) async {
    Object? firstError;
    StackTrace? firstStackTrace;

    var running = 0;
    final wakeUp = Condition();
    await for (final item in this) {
      running += 1;
      scheduleMicrotask(() async {
        try {
          await each(item);
        } catch (e, st) {
          if (firstError == null) {
            firstError = e;
            firstStackTrace = st;
          }
        } finally {
          running -= 1;
          wakeUp.notify();
        }
      });

      if (running >= concurrency) {
        await wakeUp.wait;
      }
    }

    while (running >= concurrency) {
      await wakeUp.wait;
    }

    final firstError_ = firstError;
    if (firstError_ != null) {
      return Future.error(firstError_, firstStackTrace);
    }
  }
}
