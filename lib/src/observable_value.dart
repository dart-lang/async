// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

/// A single variable with a stream emitting the variable's changing values.
///
/// Contains a single [value] which can be read and written as any other
/// variable.
///
/// Whenever the value is set, the new value is emitted on the
/// [updates] stream.
/// Further, any new listener on the [updates] stream is initially sent the
/// current [value].
///
/// Consider using immutable types for [value] since listeners will not
/// be notified if the internal state of [value] changes, only if
/// the [value] variable is written to.
///
/// Example:
/// ```dart
/// class ToggleWidget {
///   final ObservableValue<bool> _isVisible = ObservableValue(true);
///
///   // ...
///
///   Stream<bool> get visibilityChanges => _isVisible.updates;
///
///   void toggleVisibility() {
///     _isVisible.value ^= true; // XOR with true toggles value.
///   }
/// }
/// ```
abstract class ObservableValue<T> {
  /// The current value.
  ///
  /// The [updates] stream emits the current value when listened to,
  /// and the new value when `value` is set to a new value.
  abstract T value;

  /// A stream emitting the current value of [value].
  ///
  /// New listeners will receive an event containing the current value
  /// of [value] as soon as possible after listening.
  /// Every time [value] changes, they will then receive an event
  /// with the new value.
  ///
  /// This stream can be listened to multiple times.
  /// It will never emit an error event.
  /// _It's not a broadcast stream, because cancelling a subscription
  /// on the stream, and then quickly listening again, may cause the
  /// same event (the current value) to be seen twice._
  abstract final Stream<T> updates;

  /// Creates an observable value with the given initial value.
  factory ObservableValue(T initialValue) = _ObservableValue<T>;

  // Possible method to add:
  //
  // /// Prevents further updates to [value].
  // ///
  // /// The [value] can no longer be set.
  // ///
  // /// The [updates] stream will close current listeners,
  // /// and close new listeners after sending them the current value.
  // void freeze();
}

/// Default implementation of [ObservableValue].
class _ObservableValue<T> implements ObservableValue<T> {
  /// The stored value.
  T _value;

  /// Listeners waiting for updates.
  final List<MultiStreamController<T>> _listeners = [];

  /// The update stream, created when the first listener is added.
  Stream<T>? _stream;

  _ObservableValue(this._value);

  @override
  T get value => _value;
  @override
  set value(T value) {
    _value = value;
    _notify(value);
  }

  @override
  Stream<T> get updates => _stream ??= Stream<T>.multi((controller) {
        controller.add(_value);
        _listeners.add(controller);
      });

  void _notify(T value) {
    // Sends event to active listeners, and compacts listener list
    // to only contain listeners which are still active.

    // Since `add` is asynchronous, this loop will not call any user code.
    var activeCount = 0;
    for (var i = 0; i < _listeners.length; i++) {
      var controller = _listeners[i];
      if (controller.hasListener) {
        controller.add(value); // Async event, so no synchronous side effects.
        if (activeCount < i) {
          _listeners[activeCount] = controller;
        }
        activeCount++;
      }
    }
    if (activeCount < _listeners.length) _listeners.length = activeCount;
  }
}
