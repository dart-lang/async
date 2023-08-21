// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:meta/meta.dart';

/// A [Notifier] allows micro-tasks to [wait] for other micro-tasks to
/// [notify].
///
/// [Notifier] is a concurrency primitive that allows one micro-task to
/// wait for notification from another micro-task. The [Future] return from
/// [wait] will be completed the next time [notify] is called.
///
/// ```dart
/// var weather = 'rain';
/// final notifier = Notifier();
///
/// // Create a micro task to fetch the weather
/// scheduleMicrotask(() async {
///   // Infinitely loop that just keeps the weather up-to-date
///   while (true) {
///     weather = await getWeather();
///     notifier.notify();
///
///     // Sleep 5s before updating the weather again
///     await Future.delayed(Duration(seconds: 5));
///   }
/// });
///
/// // Wait for sunny weather
/// while (weather != 'sunny') {
///   await notifier.wait;
/// }
/// ```
// TODO: Apply `final` when language version for this library is bumped to 3.0
@sealed
class Notifier {
  var _completer = Completer<void>();

  /// Notify everybody waiting for notification.
  ///
  /// This will complete all futures previously returned by [wait].
  /// Calls to [wait] after this call, will not be resolved, until the
  /// next time [notify] is called.
  void notify() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  /// Wait for notification.
  ///
  /// Returns a [Future] that will complete the next time [notify] is called.
  ///
  /// The [Future] returned will always be unresolved, and it will never throw.
  /// Once [notify] is called the future will be completed, and any new calls
  /// to [wait] will return a new future. This new future will also be
  /// unresolved, until [notify] is called.
  Future<void> get wait {
    if (_completer.isCompleted) {
      _completer = Completer();
    }
    return _completer.future;
  }
}
