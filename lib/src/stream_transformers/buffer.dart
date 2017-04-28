// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:async';

/// Creates a [StreamTransformer] which collects values and emits when it sees a
/// value on [trigger].
///
/// If there are no pending values when [trigger] emits, the next value on the
/// source Stream will immediately flow through. Otherwise, the pending values
/// are released when [trigger] emits.
///
/// Errors from the source stream or the trigger are immediately forwarded to
/// the output.
StreamTransformer<T, List<T>> buffer<T>(Stream trigger) => new _Buffer(trigger);

List<T> _collectToList<T>(T element, List<T> soFar) {
  soFar ??= <T>[];
  soFar.add(element);
  return soFar;
}

/// A StreamTransformer which aggregates values and emits when it sees a value
/// on [_trigger].
///
/// If there are no pending values when [_trigger] emits the first value on the
/// source Stream will immediately flow through. Otherwise, the pending values
/// and released when [_trigger] emits.
///
/// Errors from the source stream or the trigger are immediately forwarded to
/// the output.
class _Buffer<T> implements StreamTransformer<T, List<T>> {
  final Stream _trigger;

  _Buffer(this._trigger);

  @override
  Stream<List<T>> bind(Stream<T> values) {
    StreamController<List<T>> controller;
    if (values.isBroadcast) {
      controller = new StreamController<List<T>>.broadcast();
    } else {
      controller = new StreamController<List<T>>();
    }

    List<T> currentResults;
    bool waitingForTrigger = true;
    StreamSubscription valuesSub;
    StreamSubscription triggerSub;

    cancelValues() {
      var sub = valuesSub;
      valuesSub = null;
      return sub?.cancel() ?? new Future.value();
    }

    cancelTrigger() {
      var sub = triggerSub;
      triggerSub = null;
      return sub?.cancel() ?? new Future.value();
    }

    closeController() {
      var ctl = controller;
      controller = null;
      return ctl?.close() ?? new Future.value();
    }

    emit() {
      controller.add(currentResults);
      currentResults = null;
    }

    onValue(T value) {
      currentResults = _collectToList(value, currentResults);
      if (!waitingForTrigger) {
        emit();
        waitingForTrigger = true;
      }
    }

    valuesDone() {
      valuesSub = null;
      if (currentResults == null) {
        closeController();
        cancelTrigger();
      }
    }

    onTrigger(_) {
      if (currentResults == null) {
        waitingForTrigger = false;
        return;
      }
      emit();
      if (valuesSub == null) {
        closeController();
        cancelTrigger();
      }
    }

    triggerDone() {
      cancelValues();
      closeController();
    }

    controller.onListen = () {
      if (valuesSub != null) return;
      valuesSub = values.listen(onValue,
          onError: controller.addError, onDone: valuesDone);
      if (triggerSub != null) {
        if (triggerSub.isPaused) triggerSub.resume();
      } else {
        triggerSub = _trigger.listen(onTrigger,
            onError: controller.addError, onDone: triggerDone);
      }
    };

    // Forward methods from listener
    if (!values.isBroadcast) {
      controller.onPause = () {
        valuesSub?.pause();
        triggerSub?.pause();
      };
      controller.onResume = () {
        valuesSub?.resume();
        triggerSub?.resume();
      };
      controller.onCancel =
          () => Future.wait([cancelValues(), cancelTrigger()]);
    } else {
      controller.onCancel = () {
        if (controller?.hasListener ?? false) return;
        if (_trigger.isBroadcast) {
          cancelTrigger();
        } else {
          triggerSub.pause();
        }
        cancelValues();
      };
    }
    return controller.stream;
  }
}
