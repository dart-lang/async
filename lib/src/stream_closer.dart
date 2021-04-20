// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'async_memoizer.dart';

/// A [StreamTransformer] that allows the caller to forcibly close the
/// transformed [Stream].
///
/// When [close] is called, the stream (or streams) transformed by [this] will
/// emit a done event and cancel the underlying subscription.
class StreamCloser<T> extends StreamTransformerBase<T, T> {
  /// Whether [close] has been called.
  bool get isClosed => _closeMemo.hasRun;

  /// The subscriptions to streams passed to [bind].
  final _subscriptions = <StreamSubscription<T>>{};

  /// The controllers for streams returned by [bind].
  final _controllers = <StreamController<T>>{};

  /// Closes all transformed streams.
  ///
  /// Returns a future that completes when all inner subscriptions'
  /// [StreamSubscription.cancel] futures have completed. Note that a stream's
  /// subscription won't be canceled until the transformed stream has a
  /// listener.
  ///
  /// If a transformed stream is listened to after [close] is called, the
  /// original stream will be listened to and then the subscription immediately
  /// canceled. If that cancellation throws an error, it will be silently
  /// ignored.
  Future<void> close() => _closeMemo.runOnce(() {
        var futures = _subscriptions
            .map((subscription) => subscription.cancel())
            .toList();
        _subscriptions.clear();

        for (var controller in _controllers) {
          scheduleMicrotask(controller.close);
        }
        _controllers.clear();

        return Future.wait(futures, eagerError: true);
      });
  final _closeMemo = AsyncMemoizer();

  @override
  Stream<T> bind(Stream<T> stream) {
    late StreamSubscription<T> subscription;
    late StreamController<T> controller;
    controller = StreamController(
        onListen: () {
          if (isClosed) {
            subscription = stream.listen(null);

            // Ignore errors here, because otherwise there would be no way for
            // the user to handle them gracefully.
            subscription.cancel().catchError((_) {});
          } else {
            subscription = stream.listen(controller.add,
                onError: controller.addError, onDone: () {
              _subscriptions.remove(subscription);
              _controllers.remove(controller);
              controller.close();
            });
            _subscriptions.add(subscription);
          }
        },
        onPause: () => subscription.pause(),
        onResume: () => subscription.resume(),
        onCancel: () {
          _subscriptions.remove(subscription);
          _controllers.remove(controller);
          subscription.cancel();
        },
        sync: true);

    if (isClosed) {
      controller.close();
    } else {
      _controllers.add(controller);
    }

    return controller.stream;
  }
}
