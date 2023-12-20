// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../async.dart';

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
/// This class's timing can be mocked using
/// [`fake_async`](https://pub.dev/packages/fake_async).
class AsyncCache<T> {
  /// How long cached values stay fresh.
  ///
  /// Set to `null` for ephemeral caches, which only stay alive until the
  /// future completes.
  final Duration? _duration;

  /// Cached results of a previous `fetchStream` call.
  StreamSplitter<T>? _cachedStreamSplitter;

  /// Cached results of a previous [fetch] call.
  Future<T>? _cachedValueFuture;

  /// Whether the cache will keep a future completed with an error.
  ///
  /// If `false`, a non-ephemeral cache will clear the cached future
  /// immediately if the future completes with an error, as if the
  /// caching was ephemeral.
  /// _(Ephemeral caches always clear when the future completes,
  /// so this flag has no effect on those.)_
  final bool _cacheErrors;

  /// Fires when the cache should be considered stale.
  Timer? _stale;

  /// Creates a cache that invalidates its contents after [duration] has passed.
  ///
  /// The [duration] starts counting after the Future returned by [fetch]
  /// completes, or after the Stream returned by `fetchStream` emits a done
  /// event.
  AsyncCache(Duration duration, {bool cacheErrors = true})
      : _duration = duration,
        _cacheErrors = cacheErrors;

  /// Creates a cache that invalidates after an in-flight request is complete.
  ///
  /// An ephemeral cache guarantees that a callback function will only be
  /// executed at most once concurrently. This is useful for requests for which
  /// data is updated frequently but stale data is acceptable.
  AsyncCache.ephemeral()
      : _duration = null,
        _cacheErrors = true;

  /// Returns a cached value from a previous call to [fetch], or runs [callback]
  /// to compute a new one.
  ///
  /// If [fetch] has been called recently enough, returns its previous return
  /// value. Otherwise, runs [callback] and returns its new return value.
  Future<T> fetch(Future<T> Function() callback) async {
    if (_cachedStreamSplitter != null) {
      throw StateError('Previously used to cache via `fetchStream`');
    }
    if (_cacheErrors) {
      return _cachedValueFuture ??= callback()
        ..whenComplete(_startStaleTimer).ignore();
    } else {
      return _cachedValueFuture ??= callback().then((value) {
        _startStaleTimer();
        return value;
      }, onError: (Object error, StackTrace stack) {
        invalidate();
        throw error;
      });
    }
  }

  /// Returns a cached stream from a previous call to [fetchStream], or runs
  /// [callback] to compute a new stream.
  ///
  /// If [fetchStream] has been called recently enough, returns a copy of its
  /// previous return value. Otherwise, runs [callback] and returns its new
  /// return value.
  ///
  /// Each call to this function returns a stream which replays the same events,
  /// which means that all stream events are cached until this cache is
  /// invalidated.
  ///
  /// Only starts counting time after the stream has been listened to,
  /// and it has completed with a `done` event.
  @Deprecated('Feature will be removed')
  Stream<T> fetchStream(Stream<T> Function() callback) {
    if (_cachedValueFuture != null) {
      throw StateError('Previously used to cache via `fetch`');
    }
    var splitter = _cachedStreamSplitter ??= StreamSplitter(
        callback().transform(StreamTransformer.fromHandlers(handleDone: (sink) {
      _startStaleTimer();
      sink.close();
    })));
    return splitter.split();
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
    var duration = _duration;
    if (duration != null) {
      _stale = Timer(duration, invalidate);
    } else {
      invalidate();
    }
  }
}
