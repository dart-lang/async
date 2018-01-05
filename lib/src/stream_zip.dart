// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";

/// A stream that combines the values of other streams.
///
/// This emits lists of collected values from each input stream. The first list
/// contains the first value emitted by each stream, the second contains the
/// second value, and so on. The lists have the same ordering as the iterable
/// passed to [new StreamZip].
///
/// Any errors from any of the streams are forwarded directly to this stream.
class StreamZip<T> extends Stream<List<T>> {
  final Iterable<Stream<T>> _streams;

  StreamZip(Iterable<Stream<T>> streams) : _streams = streams;

  StreamSubscription<List<T>> listen(void onData(List<T> data),
      {Function onError, void onDone(), bool cancelOnError}) {
    cancelOnError = identical(true, cancelOnError);
    var subscriptions = <StreamSubscription<T>>[];
    StreamController<List<T>> controller;
    List<T> current;
    int dataCount = 0;

    /// Called for each data from a subscription in [subscriptions].
    void handleData(int index, T data) {
      current[index] = data;
      dataCount++;
      if (dataCount == subscriptions.length) {
        var data = current;
        current = new List(subscriptions.length);
        dataCount = 0;
        for (int i = 0; i < subscriptions.length; i++) {
          if (i != index) subscriptions[i].resume();
        }
        controller.add(data);
      } else {
        subscriptions[index].pause();
      }
    }

    /// Called for each error from a subscription in [subscriptions].
    /// Except if [cancelOnError] is true, in which case the function below
    /// is used instead.
    void handleError(Object error, StackTrace stackTrace) {
      controller.addError(error, stackTrace);
    }

    /// Called when a subscription has an error and [cancelOnError] is true.
    ///
    /// Prematurely cancels all subscriptions since we know that we won't
    /// be needing any more values.
    void handleErrorCancel(Object error, StackTrace stackTrace) {
      for (int i = 0; i < subscriptions.length; i++) {
        subscriptions[i].cancel();
      }
      controller.addError(error, stackTrace);
    }

    void handleDone() {
      for (int i = 0; i < subscriptions.length; i++) {
        subscriptions[i].cancel();
      }
      controller.close();
    }

    try {
      for (var stream in _streams) {
        int index = subscriptions.length;
        subscriptions.add(stream.listen((data) {
          handleData(index, data);
        },
            onError: cancelOnError ? handleError : handleErrorCancel,
            onDone: handleDone,
            cancelOnError: cancelOnError));
      }
    } catch (e) {
      for (int i = subscriptions.length - 1; i >= 0; i--) {
        subscriptions[i].cancel();
      }
      rethrow;
    }

    current = new List(subscriptions.length);

    controller = new StreamController<List<T>>(onPause: () {
      for (int i = 0; i < subscriptions.length; i++) {
        // This may pause some subscriptions more than once.
        // These will not be resumed by onResume below, but must wait for the
        // next round.
        subscriptions[i].pause();
      }
    }, onResume: () {
      for (int i = 0; i < subscriptions.length; i++) {
        subscriptions[i].resume();
      }
    }, onCancel: () {
      for (int i = 0; i < subscriptions.length; i++) {
        // Canceling more than once is safe.
        subscriptions[i].cancel();
      }
    });

    if (subscriptions.isEmpty) {
      controller.close();
    }
    return controller.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }
}
