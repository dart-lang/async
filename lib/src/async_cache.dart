// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';

/// Runs asynchronous functions and caches the result for a period of time.
///
/// This class exists to cover the pattern of having potentially expensive code
/// such as file I/O, network access, or isolate computation that's unlikely to
/// change quickly run fewer times. For example:
///
/// ```dart
/// final _usersCache = new AsyncCache<List<String>>(const Duration(hours: 1));
///
/// /// Uses the cache if it exists, otherwise calls the closure:
/// Future<List<String>> get onlineUsers => _usersCache.fetch(() {
///   // Actually fetch online users here.
/// });
/// ```
///
/// This class's timing can be mocked using [`fake_async`][fake_async].
///
/// [fake_async]: https://pub.dev/packages/fake_async
class AsyncCache<T> {
  /// How long cached values stay fresh.
  final Duration _duration;

  /// Cached results of a previous [fetchStream] call.
  StreamSplitter<T> _cachedStreamSplitter;

  /// Cached results of a previous [fetch] call.
  Future<T> _cachedValueFuture;

  /// Fires when the cache should be considered stale.
  Timer _stale;

  /// Creates a cache that invalidates its contents after [duration] has passed.
  ///
  /// The [duration] starts counting after the Future returned by [fetch]
  /// completes, or after the Stream returned by [fetchStream] emits a done
  /// event.
  AsyncCache(this._duration);

  /// Creates a cache that invalidates after an in-flight request is complete.
  ///
  /// An ephemeral cache guarantees that a callback function will only be
  /// executed at most once concurrently. This is useful for requests for which
  /// data is updated frequently but stale data is acceptable.
  factory AsyncCache.ephemeral() => AsyncCache(Duration.zero);

  /// Returns a cached value from a previous call to [fetch], or runs [callback]
  /// to compute a new one.
  ///
  /// If [fetch] has been called recently enough, returns its previous return
  /// value. Otherwise, runs [callback] and returns its new return value.
  Future<T> fetch(Future<T> Function() callback) async {
    if (_cachedStreamSplitter != null) {
      throw StateError('Previously used to cache via `fetchStream`');
    }
    if (_cachedValueFuture == null) {
      _cachedValueFuture = callback();
      await _cachedValueFuture;
      _startStaleTimer();
    }
    return _cachedValueFuture;
  }

  /// Returns a cached stream from a previous call to [fetchStream], or runs
  /// [callback] to compute a new stream.
  ///
  /// If [fetchStream] has been called recently enough, returns a copy of its
  /// previous return value. Otherwise, runs [callback] and returns its new
  /// return value.
  Stream<T> fetchStream(Stream<T> Function() callback) {
    if (_cachedValueFuture != null) {
      throw StateError('Previously used to cache via `fetch`');
    }
    _cachedStreamSplitter ??= StreamSplitter(
        callback().transform(StreamTransformer.fromHandlers(handleDone: (sink) {
      _startStaleTimer();
      sink.close();
    })));
    return _cachedStreamSplitter.split();
  }

  /// Removes any cached value.
  void invalidate() {
    // TODO: This does not return a future, but probably should.
    _cachedValueFuture = null;
    // TODO: This does not await, but probably should.
    _cachedStreamSplitter?.close();
    _cachedStreamSplitter = null;
    _stale?.cancel();
    _stale = null;
  }

  void _startStaleTimer() {
    _stale = Timer(_duration, invalidate);
  }
}
