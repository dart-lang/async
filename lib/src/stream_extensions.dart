// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'notifier.dart';

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

  /// Call [each] for each item in this stream with [maxParallel] invocations.
  ///
  /// This method will invoke [each] for each item in this stream, and wait for
  /// all futures from [each] to be resolved. [parallelForEach] will call [each]
  /// in parallel, but never more then [maxParallel].
  ///
  /// If [each] throws and [onError] rethrows (default behavior), then
  /// [parallelForEach] will wait for ongoing [each] invocations to finish,
  /// before throw the first error.
  ///
  /// If [onError] does not throw, then iteration will not be interrupted and
  /// errors from [each] will be ignored.
  ///
  /// ```dart
  /// // Count size of all files in the current folder
  /// var folderSize = 0;
  /// // Use parallelForEach to read at-most 5 files at the same time.
  /// await Directory.current.list().parallelForEach(5, (item) async {
  ///   if (item is File) {
  ///     final bytes = await item.readAsBytes();
  ///     folderSize += bytes.length;
  ///   }
  /// });
  /// print('Folder size: $folderSize');
  /// ```
  Future<void> parallelForEach(
    int maxParallel,
    FutureOr<void> Function(T item) each, {
    FutureOr<void> Function(Object e, StackTrace? st) onError = Future.error,
  }) async {
    // Track the first error, so we rethrow when we're done.
    Object? firstError;
    StackTrace? firstStackTrace;

    // Track number of running items.
    var running = 0;
    final itemDone = Notifier();

    try {
      var doBreak = false;
      await for (final item in this) {
        // For each item we increment [running] and call [each]
        running += 1;
        unawaited(() async {
          try {
            await each(item);
          } catch (e, st) {
            try {
              // If [onError] doesn't throw, we'll just continue.
              await onError(e, st);
            } catch (e, st) {
              doBreak = true;
              if (firstError == null) {
                firstError = e;
                firstStackTrace = st;
              }
            }
          } finally {
            // When [each] is done, we decrement [running] and notify
            running -= 1;
            itemDone.notify();
          }
        }());

        if (running >= maxParallel) {
          await itemDone.wait;
        }
        if (doBreak) {
          break;
        }
      }
    } finally {
      // Wait for all items to be finished
      while (running > 0) {
        await itemDone.wait;
      }
    }

    // If an error happened, then we rethrow the first one.
    final firstError_ = firstError;
    final firstStackTrace_ = firstStackTrace;
    if (firstError_ != null && firstStackTrace_ != null) {
      Error.throwWithStackTrace(firstError_, firstStackTrace_);
    }
  }
}
