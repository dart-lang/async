// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

/// Utility extensions on [Stream].
extension StreamExtensions<T> on Stream<T> {
  /// Creates a stream whose elements are contiguous slices of [this].
  ///
  /// Each slice is [length] elements long, except for the last one which may be
  /// shorter if [this] emits too few elements. Each slice begins after the
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

  /// Returns the first data or error event emitted by [this] if it emits any,
  /// or `null` if it emits a done event first.
  Future<T?> get firstOrNull {
    var completer = Completer<T?>.sync();
    late StreamSubscription<T> subscription;
    subscription = listen((event) {
      subscription.cancel();
      completer.complete(event);
    }, onError: (Object error, StackTrace stackTrace) {
      subscription.cancel();
      completer.completeError(error, stackTrace);
    }, onDone: () {
      completer.complete(null);
    });
    return completer.future;
  }
}
