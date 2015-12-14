// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library async.lazy_stream;

import "dart:async";

import "stream_completer.dart";

/// A [Stream] wrapper that forwards to another [Stream] that's initialized
/// lazily.
///
/// This class allows a concrete `Stream` to be created only once it has a
/// listener. It's useful to wrapping APIs that do expensive computation to
/// produce a `Stream`.
class LazyStream<T> extends Stream<T> {
  /// The callback that's called to create the inner stream.
  ZoneCallback _callback;

  /// Creates a single-subscription `Stream` that calls [callback] when it gets
  /// a listener and forwards to the returned stream.
  ///
  /// The [callback] may return a `Stream` or a `Future<Stream>`.
  LazyStream(callback()) : _callback = callback {
    // Explicitly check for null because we null out [_callback] internally.
    if (_callback == null) throw new ArgumentError.notNull('callback');
  }

  StreamSubscription<T> listen(void onData(T event),
                               {Function onError,
                                void onDone(),
                                bool cancelOnError}) {
    if (_callback == null) {
      throw new StateError("Stream has already been listened to.");
    }

    // Null out the callback before we invoke it to ensure that even while
    // running it, this can't be called twice.
    var callback = _callback;
    _callback = null;
    var result = callback();

    Stream stream = result is Future
        ? StreamCompleter.fromFuture(result)
        : result;

    return stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}
