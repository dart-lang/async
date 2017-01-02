// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

typedef DateTime _GetNow();

/// Runs asynchronous functions and caches the result for a period of time.
///
/// This class exists to cover the pattern of having potentially expensive code
/// such as file I/O, network access, or isolate computation run fewer times in
/// an application or process.
///
/// ## Example use with a `Future`:
/// ```dart
/// final _usersCache = new AsyncCache<List<String>>();
///
/// /// Runs the actual expensive code.
/// Future<List<String>> _getOnlineUsers() => ...
///
/// /// Uses the cache if it exists, otherwise calls `_getOnlineUsers`.
/// Future<List<String>> getOnlineUsers() => _usersCache.fetch(_getOnlineUsers);
/// ```
class AsyncCache<T> {
  static DateTime _defaultNow() => new DateTime.now();

  final Duration _duration;
  final _GetNow _getNow;

  List<T> _cachedStreamValues;
  Future _fetchingStream;

  Future<T> _cachedValueFuture;
  DateTime _cachedExpiration;

  /// Creates a cache that invalidates contents after [duration] has passed.
  ///
  /// For _testing_, a custom `now` function may be provided.
  factory AsyncCache(Duration duration, {DateTime now()}) = AsyncCache<T>._;

  /// Creates a cache that invalidates after an in-flight request is complete.
  ///
  /// An ephemeral cache guarantees that a callback function will only be
  /// executed at most once concurrently. This is useful for requests which data
  /// is updated frequently but the cost of making multiple requests without
  /// previous completing yet is prohibitive or unwanted.
  ///
  /// For _testing_, a custom `now` function may be provided.
  factory AsyncCache.ephemeral({DateTime now()}) =>
      new AsyncCache._(Duration.ZERO);

  // Prevent inheritance. This allows using a redirecting factory constructor
  // with different implementations in the future without a breaking API change.
  AsyncCache._(this._duration, {DateTime now(): _defaultNow,})
      : _getNow = now;

  /// Returns a cached value or runs [callback] to compute a new one.
  ///
  /// If [callback] has been run recently enough, returns its previous return
  /// value. Otherwise, runs [callback] and returns its new return value.
  Future<T> fetch(Future<T> callback()) async {
    _invalidateWhenStale();
    var result = await (_cachedValueFuture ??= callback());
    _cachedExpiration ??= _getNow().add(_duration);
    return result;
  }

  /// Returns a cached stream or runs [callback] to compute a new stream.
  ///
  /// If [callback] has been run recently enough, returns its previous return
  /// value. Otherwise, runs [callback] and returns its new return value.
  ///
  /// If a stream is currently being fetched, waits until the _done_ event and
  /// then returns the cached value.
  Stream<T> fetchStream(Stream<T> callback()) async* {
    _invalidateWhenStale();
    if (_fetchingStream != null) {
      await _fetchingStream;
    }
    if (_cachedStreamValues != null) {
      yield* new Stream<T>.fromIterable(_cachedStreamValues);
      return;
    }
    var fetching = new Completer();
    _fetchingStream = fetching.future;
    var values = <T>[];
    await for (var result in callback()) {
      values.add(result);
      yield result;
    }
    _cachedStreamValues = values;
    _cachedExpiration ??= _getNow().add(_duration);
    fetching.complete();
  }

  /// Removes any cached value, and returns `true` if a cached value existed.
  Future<bool> invalidate() {
    if (_cachedExpiration == null) {
      return new Future<bool>.value(false);
    }
    _cachedExpiration = null;
    _cachedValueFuture = null;
    _cachedStreamValues = null;
    return new Future<bool>.value(true);
  }

  void _invalidateWhenStale() {
    if (_cachedExpiration != null && !_cachedExpiration.isAfter(_getNow())) {
      invalidate();
    }
  }
}
