// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

/// A non-periodic timer that can be restarted any number of times.
///
/// Once restarted (via [reset]), the timer counts down from its original
/// duration again.
class RestartableTimer implements Timer {
  /// The duration of the timer.
  final Duration _duration;

  /// The callback to call when the timer fires.
  final ZoneCallback _callback;

  /// The timer for the current or most recent countdown.
  ///
  /// This timer is canceled and overwritten every time this [RestartableTimer]
  /// is reset.
  Timer _timer;

  /// Creates a new timer.
  ///
  /// The [callback] function is invoked after the given [duration]. Unlike a
  /// normal non-periodic [Timer], [callback] may be called more than once.
  RestartableTimer(this._duration, this._callback) {
    _timer = new Timer(_duration, _callback);
  }

  bool get isActive => _timer.isActive;

  /// Restarts the timer so that it counts down from its original duration
  /// again.
  ///
  /// This restarts the timer even if it has already fired or has been canceled.
  void reset() {
    _timer.cancel();
    _timer = new Timer(_duration, _callback);
  }

  void cancel() {
    _timer.cancel();
  }

  @override
  // TODO: Dart 2.0 requires this method to be implemented.
  // See https://github.com/dart-lang/sdk/issues/31664
  // ignore: override_on_non_overriding_getter
  int get tick {
    throw new UnimplementedError("tick");
  }
}
