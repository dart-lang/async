// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

/// An [EventSink] which forwards event sink calls to an [EventHandler].
///
/// The [close] method rof [EventHandler.onDone] can return a future,
/// but [EventSink.close] doesn't.
/// Code expecting an [EventSink] won't check for such a future,
/// and an [EventHandler] used with an [EventSinkAdapter] should never
/// return a future.
class EventSinkAdapter<T> implements EventSink<T> {
  final EventHandler<T> _handler;
  bool _closed = false;

  /// Creates an event sink forwarding events to [handler].
  EventSinkAdapter(EventHandler<T> handler) : _handler = handler;

  @override
  void add(T event) {
    _checkCanAdd();
    _handler.onData(event);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _checkCanAdd();
    _handler.onError(error, stackTrace ?? _defaultStack(error));
  }

  @override
  void close() {
    if (!_closed) {
      _closed = true;
      _handler.onDone();
    }
  }

  void _checkCanAdd() {
    if (_closed) {
      throw StateError('Cannot add event after closing');
    }
  }
}

/// A [StreamSink] which forwards stream sink calls to an [EventHandler].
class StreamSinkAdapter<T> implements StreamSink<T> {
  final EventHandler<T> _handler;
  final Completer<void> _doneFuture = Completer();
  bool _addingStream = false;

  /// Creates a stream sink which forwards events to [handler].
  StreamSinkAdapter(EventHandler<T> handler) : _handler = handler;

  @override
  Future<void> addStream(Stream<T> stream) async {
    _checkCanAdd();
    var completer = Completer<void>.sync();
    _addingStream = true;
    stream.listen(_handler.onData, onError: _handler.onError, onDone: () {
      _addingStream = false;
      completer.complete(null);
    });
    return completer.future;
  }

  void _checkCanAdd() {
    if (_addingStream) {
      throw StateError('Cannot add event while adding a stream');
    }
    if (_doneFuture.isCompleted) {
      throw StateError('Cannot add event after closing');
    }
  }

  @override
  Future<void> close() {
    if (_addingStream) {
      throw StateError('Cannot add event while adding a stream');
    }
    if (!_doneFuture.isCompleted) _doneFuture.complete(_handler.onDone());
    return _doneFuture.future;
  }

  @override
  Future get done => _doneFuture.future;

  @override
  void add(T event) {
    _checkCanAdd();
    _handler.onData(event);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _checkCanAdd();
    _handler.onError(error, stackTrace ?? _defaultStack(error));
  }
}

/// Helper function to ensure a stack trace is available.
///
/// If [error] is an [Error], its [Error.stackTrace] is used.
/// If [error] is not an [Error], or its [Error.stackTrace] is `null`,
/// the [StackTrace.current] trace is used instead.
StackTrace _defaultStack(Object error) =>
    (error is Error ? error.stackTrace : null) ?? StackTrace.current;

/// Generalized unified callback handler for events from a stream.
///
/// A subclass can extend this class an override any of the
/// [onData], [onError] or [onDone] methods.
/// The default implementation simply ignores the events.
class EventHandler<T> {
  EventHandler();

  /// Creates an event handler from the provided callbacks.
  ///
  /// Any callback not provided means that the corresponding event
  /// has no effect.
  factory EventHandler.fromCallbacks(
      {void Function(T)? onData,
      void Function(Object, StackTrace)? onError,
      Future<void>? Function()? onDone}) = CallbackEventHandler<T>;

  /// Called for data events.
  void onData(T value) {}

  /// Called for error events.
  void onError(Object error, StackTrace stackTrace) {}

  /// Called for the done event.
  Future<void>? onDone() {
    return null;
  }
}

/// An event handler which forwards events to provided callback functions.
class CallbackEventHandler<T> implements EventHandler<T> {
  final void Function(T)? _onData;
  final void Function(Object, StackTrace)? _onError;
  final Future<void>? Function()? _onDone;

  /// Creates an event handler forwarding to the provided callback fcunctions.
  CallbackEventHandler(
      {void Function(T)? onData,
      void Function(Object, StackTrace)? onError,
      Future<void>? Function()? onDone})
      : _onData = onData,
        _onError = onError,
        _onDone = onDone;

  @override
  void onData(T value) {
    _onData?.call(value);
  }

  @override
  Future<void>? onDone() => _onDone?.call();

  @override
  void onError(Object error, StackTrace stackTrace) {
    _onError?.call(error, stackTrace);
  }
}

/// An [EventHandler] where the function called for events can be changed.
///
/// This class is not zone aware. The functions stored in [dataHandler],
/// [errorHandler] and [doneHandler] are called in the current zone
/// at the time when [onData], [onError] or [onDone] is called.
class MutableCallbackEventHandler<T> implements EventHandler<T> {
  /// The data handler called by [onData], if any.
  ///
  /// When set to `null`, data events have no effect.
  void Function(T)? dataHandler;

  /// The error handler called by [onError], if any.
  ///
  /// When set to `null`, error events have no effect.
  void Function(Object, StackTrace)? errorHandler;

  /// The done handler called by [onDone], if any.
  ///
  /// When set to `null`, done events have no effect.
  Future<void>? Function()? doneHandler;

  /// Creates a mutable event handler initialized with any provided callbacks.
  MutableCallbackEventHandler(
      {void Function(T)? onData,
      void Function(Object, StackTrace)? onError,
      Future<void>? Function()? onDone})
      : dataHandler = onData,
        errorHandler = onError,
        doneHandler = onDone;

  @override
  void onData(T value) {
    dataHandler?.call(value);
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    errorHandler?.call(error, stackTrace);
  }

  @override
  Future<void>? onDone() => doneHandler?.call();
}
