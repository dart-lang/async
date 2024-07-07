// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../async.dart';

/// A class that wraps [AsyncMemoizer] it provides the same behavior where
/// you need a result of a function to be cached but for a short duration.
class TimedAsyncMemoizer<T> {
  TimedAsyncMemoizer({
    this.expiryDuration = const Duration(seconds: 5),
  });

  final Duration expiryDuration;

  AsyncMemoizer<T>? _memoizer;
  late DateTime _expiryTime;

  /// Returns true if `DateTime.now()` is after [_expiryTime] or
  /// if [_memoizer] is null.
  bool get isExpired {
    if (_memoizer == null) {
      return true;
    }

    return DateTime.now().isAfter(_expiryTime);
  }

  /// Runs the function [computation], if it hasn't been run before
  /// and if the cache has expired.
  ///
  /// If it has already been run and cache has not expired it will return the
  /// cached result.
  Future<T> run(FutureOr<T> Function() computation) {
    if (isExpired) {
      _init();
    }

    assert(_memoizer != null);

    return _memoizer!.runOnce(computation);
  }

  void _init() {
    _memoizer = AsyncMemoizer();
    _expiryTime = DateTime.now().add(expiryDuration);
  }
}
