// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';

import 'cancelable_operation.dart';
import 'result/result.dart';
import 'stream_completer.dart';
import 'subscription_stream.dart';

/// An asynchronous pull-based interface for accessing stream events.
///
/// Wraps a stream and makes individual events available on request.
///
/// You can request (and reserve) one or more events from the stream,
/// and after all previous requests have been fulfilled, stream events
/// go towards fulfilling your request.
///
/// For example, if you ask for [next] two times, the returned futures
/// will be completed by the next two unrequested events from the stream.
///
/// The stream subscription is paused when there are no active
/// requests.
///
/// Some streams, including broadcast streams, will buffer
/// events while paused, so waiting too long between requests may
/// cause memory bloat somewhere else.
///
/// This is similar to, but more convenient than, a [StreamIterator].
/// A `StreamIterator` requires you to manually check when a new event is
/// available and you can only access the value of that event until you
/// check for the next one. A `StreamQueue` allows you to request, for example,
/// three events at a time, either individually, as a group using [take]
/// or [skip], or in any combination.
///
/// You can also ask to have the [rest] of the stream provided as
/// a new stream. This allows, for example, taking the first event
/// out of a stream and continuing to use the rest of the stream as a stream.
///
/// Example:
///
///     var events = StreamQueue<String>(someStreamOfLines);
///     var first = await events.next;
///     while (first.startsWith('#')) {
///       // Skip comments.
///       first = await events.next;
///     }
///
///     if (first.startsWith(MAGIC_MARKER)) {
///       var headerCount =
///           first.parseInt(first.substring(MAGIC_MARKER.length + 1));
///       handleMessage(headers: await events.take(headerCount),
///                     body: events.rest);
///       return;
///     }
///     // Error handling.
///
/// When you need no further events the `StreamQueue` should be closed
/// using [cancel]. This releases the underlying stream subscription.
class _StreamStreamQueue<T> extends StreamQueue<T> {
  final Stream<T> _source;

  /// Subscription on [_source] while listening for events.
  ///
  /// Set to subscription when listening, and set to `null` when the
  /// subscription is done (and [_isDone] is set to true).
  StreamSubscription<T>? _subscription;

  // Private generative constructor to avoid subclasses.
  _StreamStreamQueue(this._source) : super._() {
    // Start listening immediately if we could otherwise lose events.
    if (_source.isBroadcast) {
      _ensureListening();
      _pause();
    }
  }

  /// Requests that the event source pauses events.
  ///
  /// This is called automatically when the request queue is empty.
  ///
  /// The event source is restarted by the next call to [_ensureListening].
  @override
  void _pause() {
    _subscription?.pause();
  }

  /// Ensures that we are listening on events from the event source.
  ///
  /// Starts listening for the first time or resumes after a [_pause].
  ///
  /// Is called automatically if a request requires more events.
  @override
  void _ensureListening() {
    if (_isDone) return;
    var subscription = _subscription;
    if (subscription != null) {
      subscription.resume();
    } else {
      _subscription = _source.listen((data) {
        _addResult(Result.value(data));
      }, onError: (Object error, StackTrace stackTrace) {
        _addResult(Result.error(error, stackTrace));
      }, onDone: () {
        _subscription = null;
        _close();
      });
    }
  }

  /// Cancels the underlying event source.
  @override
  Future? _cancel() {
    if (_isDone) return null;
    var cancelFuture = (_subscription ?? _source.listen(null)).cancel();
    _close(); // Sets _isDone, updates requests.
    return cancelFuture;
  }

  @override
  Stream<T> get rest {
    _checkNotClosed();
    var request = _StreamRestRequest<T>(this);
    _setClosed();
    _addRequest(request);
    return request.stream;
  }

  /// Extracts a stream from the event source and makes this stream queue
  /// unusable.
  ///
  /// Can only be used by the very last request (the stream queue must
  /// be closed by that request).
  /// Only used by [rest].
  Stream<T> _extractStream() {
    assert(_isClosed);
    if (_isDone) {
      return Stream<T>.empty();
    }
    _setDone();

    var subscription = _subscription;
    if (subscription == null) {
      return _source;
    }
    _subscription = null;

    var wasPaused = subscription.isPaused;
    var result = SubscriptionStream<T>(subscription);
    // Resume after creating stream because that pauses the subscription too.
    // This way there won't be a short resumption in the middle.
    if (wasPaused) subscription.resume();
    return result;
  }
}

class StreamQueue<T> {
  // This class maintains two queues: one of events and one of requests.
  // The active request (the one in front of the queue) is called with
  // the current event queue when it becomes active, every time a
  // new event arrives, and when the event source closes.
  //
  // If the request returns `true`, it's complete and will be removed from the
  // request queue.
  // If the request returns `false`, it needs more events, and will be called
  // again when new events are available. It may trigger a call itself by
  // calling [_updateRequests].
  // The request can remove events that it uses, or keep them in the event
  // queue until it has all that it needs.
  //
  // This model is very flexible and easily extensible.
  // It allows requests that don't consume events (like [hasNext]) or
  // potentially a request that takes either five or zero events, determined
  // by the content of the fifth event.

  /// Create a `StreamQueue` of the events of [source].
  factory StreamQueue(Stream<T> source) = _StreamStreamQueue<T>;

  StreamQueue._();

  StreamQueue._init(Iterable<Result<T>> initialEvents, bool isDone) {
    _eventQueue.addAll(initialEvents);
    _eventsReceived = _eventQueue.length;
    if (isDone) _setClosed();
  }

  static const int _flagDone = 1;
  static const int _flagClosed = 2;
  int _flags = 0;

  /// Whether the event source is done.
  bool get _isDone => _flags & _flagDone != 0;

  void _setDone() {
    _flags |= _flagDone;
  }

  /// Whether a closing operation has been performed on the stream queue.
  ///
  /// Closing operations are [cancel] and [rest].
  bool get _isClosed => _flags & _flagClosed != 0;

  void _setClosed() {
    _flags |= _flagClosed;
  }

  Future? _cancel() {
    if (_isDone) return null;
    _close();
    return Future<void>.value(null);
  }

  /// The number of events dispatched by this queue.
  ///
  /// This counts error events. It doesn't count done events, or events
  /// dispatched to a stream returned by [rest].
  int get eventsDispatched => _eventsReceived - _eventQueue.length;

  /// The number of events received by this queue.
  var _eventsReceived = 0;

  /// Queue of events not used by a request yet.
  final Queue<Result<T>> _eventQueue = Queue();

  /// Queue of pending requests.
  ///
  /// Access through methods below to ensure consistency.
  final Queue<_EventRequest> _requestQueue = Queue();

  /// Whether the stream has any more events.
  ///
  /// Returns a future that completes with `true` if the stream has any
  /// more events, whether data or error.
  /// If the stream closes without producing any more events, the returned
  /// future completes with `false`.
  ///
  /// Can be used before using [next] to avoid getting an error in the
  /// future returned by `next` in the case where there are no more events.
  /// Another alternative is to use `take(1)` which returns either zero or
  /// one events.
  Future<bool> get hasNext {
    _checkNotClosed();
    var hasNextRequest = _HasNextRequest<T>();
    _addRequest(hasNextRequest);
    return hasNextRequest.future;
  }

  /// Look at the next [count] data events without consuming them.
  ///
  /// Works like [take] except that the events are left in the queue.
  /// If one of the next [count] events is an error, the returned future
  /// completes with this error, and the error is still left in the queue.
  Future<List<T>> lookAhead(int count) {
    RangeError.checkNotNegative(count, 'count');
    _checkNotClosed();
    var request = _LookAheadRequest<T>(count);
    _addRequest(request);
    return request.future;
  }

  /// Requests the next (yet unrequested) event from the stream.
  ///
  /// When the requested event arrives, the returned future is completed with
  /// the event.
  /// If the event is a data event, the returned future completes
  /// with its value.
  /// If the event is an error event, the returned future completes with
  /// its error and stack trace.
  /// If the stream closes before an event arrives, the returned future
  /// completes with a [StateError].
  ///
  /// It's possible to have several pending [next] calls (or other requests),
  /// and they will be completed in the order they were requested, by the
  /// first events that were not consumed by previous requeusts.
  Future<T> get next {
    _checkNotClosed();
    var nextRequest = _NextRequest<T>();
    _addRequest(nextRequest);
    return nextRequest.future;
  }

  /// Looks at the next (yet unrequested) event from the stream.
  ///
  /// Like [next] except that the event is not consumed.
  /// If the next event is an error event, it stays in the queue.
  Future<T> get peek {
    _checkNotClosed();
    var nextRequest = _PeekRequest<T>();
    _addRequest(nextRequest);
    return nextRequest.future;
  }

  /// A stream of all the remaning events of the source stream.
  ///
  /// All requested [next], [skip] or [take] operations are completed
  /// first, and then any remaining events are provided as events of
  /// the returned stream.
  ///
  /// Using `rest` closes this stream queue. After getting the
  /// `rest` the caller may no longer request other events, like
  /// after calling [cancel].
  Stream<T> get rest {
    _checkNotClosed();
    var request = _RestRequest<T>();
    _setClosed();
    _addRequest(request);
    return request.stream;
  }

  /// Skips the next [count] *data* events.
  ///
  /// The [count] must be non-negative.
  ///
  /// When successful, this is equivalent to using [take]
  /// and ignoring the result.
  ///
  /// If an error occurs before `count` data events have been skipped,
  /// the returned future completes with that error instead.
  ///
  /// If the stream closes before `count` data events,
  /// the remaining unskipped event count is returned.
  /// If the returned future completes with the integer `0`,
  /// then all events were succssfully skipped. If the value
  /// is greater than zero then the stream ended early.
  Future<int> skip(int count) {
    RangeError.checkNotNegative(count, 'count');
    _checkNotClosed();
    var request = _SkipRequest<T>(count);
    _addRequest(request);
    return request.future;
  }

  /// Requests the next [count] data events as a list.
  ///
  /// The [count] must be non-negative.
  ///
  /// Equivalent to calling [next] `count` times and
  /// storing the data values in a list.
  ///
  /// If an error occurs before `count` data events has
  /// been collected, the returned future completes with
  /// that error instead.
  ///
  /// If the stream closes before `count` data events,
  /// the returned future completes with the list
  /// of data collected so far. That is, the returned
  /// list may have fewer than [count] elements.
  Future<List<T>> take(int count) {
    RangeError.checkNotNegative(count, 'count');
    _checkNotClosed();
    var request = _TakeRequest<T>(count);
    _addRequest(request);
    return request.future;
  }

  /// Requests a transaction that can conditionally consume events.
  ///
  /// The transaction can create copies of this queue at the current position
  /// using [StreamQueueTransaction.newQueue]. Each of these queues is
  /// independent of one another and of the parent queue. The transaction
  /// finishes when one of two methods is called:
  ///
  /// * [StreamQueueTransaction.commit] updates the parent queue's position to
  ///   match that of one of the copies.
  ///
  /// * [StreamQueueTransaction.reject] causes the parent queue to continue as
  ///   though [startTransaction] hadn't been called.
  ///
  /// Until the transaction finishes, this queue won't emit any events.
  ///
  /// See also [withTransaction] and [cancelable].
  ///
  /// ```dart
  /// /// Consumes all empty lines from the beginning of [lines].
  /// Future<void> consumeEmptyLines(StreamQueue<String> lines) async {
  ///   while (await lines.hasNext) {
  ///     var transaction = lines.startTransaction();
  ///     var queue = transaction.newQueue();
  ///     if ((await queue.next).isNotEmpty) {
  ///       transaction.reject();
  ///       return;
  ///     } else {
  ///       transaction.commit(queue);
  ///     }
  ///   }
  /// }
  /// ```
  StreamQueueTransaction<T> startTransaction() {
    _checkNotClosed();

    var request = _TransactionRequest(this);
    _addRequest(request);
    return request.transaction;
  }

  /// Passes a copy of this queue to [callback], and updates this queue to match
  /// the copy's position if [callback] returns `true`.
  ///
  /// This queue won't emit any events until [callback] returns. If it returns
  /// `false`, this queue continues as though [withTransaction] hadn't been
  /// called. If it throws an error, this updates this queue to match the copy's
  /// position and throws the error from the returned `Future`.
  ///
  /// Returns the same value as [callback].
  ///
  /// See also [startTransaction] and [cancelable].
  ///
  /// ```dart
  /// /// Consumes all empty lines from the beginning of [lines].
  /// Future<void> consumeEmptyLines(StreamQueue<String> lines) async {
  ///   while (await lines.hasNext) {
  ///     // Consume a line if it's empty, otherwise return.
  ///     if (!await lines.withTransaction(
  ///         (queue) async => (await queue.next).isEmpty)) {
  ///       return;
  ///     }
  ///   }
  /// }
  /// ```
  Future<bool> withTransaction(
      Future<bool> Function(StreamQueue<T>) callback) async {
    var transaction = startTransaction();

    var queue = transaction.newQueue();
    bool result;
    try {
      result = await callback(queue);
    } catch (_) {
      transaction.commit(queue);
      rethrow;
    }
    if (result) {
      transaction.commit(queue);
    } else {
      transaction.reject();
    }
    return result;
  }

  /// Passes a copy of this queue to [callback], and updates this queue to match
  /// the copy's position once [callback] completes.
  ///
  /// If the returned [CancelableOperation] is canceled, this queue instead
  /// continues as though [cancelable] hadn't been called. Otherwise, it emits
  /// the same value or error as [callback].
  ///
  /// See also [startTransaction] and [withTransaction].
  ///
  /// ```dart
  /// final _stdinQueue = StreamQueue(stdin);
  ///
  /// /// Returns an operation that completes when the user sends a line to
  /// /// standard input.
  /// ///
  /// /// If the operation is canceled, stops waiting for user input.
  /// CancelableOperation<String> nextStdinLine() =>
  ///     _stdinQueue.cancelable((queue) => queue.next);
  /// ```
  CancelableOperation<S> cancelable<S>(
      Future<S> Function(StreamQueue<T>) callback) {
    var transaction = startTransaction();
    var completer = CancelableCompleter<S>(onCancel: () {
      transaction.reject();
    });

    var queue = transaction.newQueue();
    completer.complete(callback(queue).whenComplete(() {
      if (!completer.isCanceled) transaction.commit(queue);
    }));

    return completer.operation;
  }

  /// Cancels the underlying event source.
  ///
  /// If [immediate] is `false` (the default), the cancel operation waits until
  /// all previously requested events have been processed, then it cancels the
  /// subscription providing the events.
  ///
  /// If [immediate] is `true`, the source is instead canceled
  /// immediately. Any pending requests are completed as though the underlying
  /// stream had closed.
  ///
  /// The returned future completes with the result of calling
  /// `cancel` on the subscription to the source stream, if any.
  ///
  /// After calling `cancel`, no further events can be requested.
  /// None of [lookAhead], [next], [peek], [rest], [skip], [take] or [cancel]
  /// may be called again.
  Future? cancel({bool immediate = false}) {
    _checkNotClosed();
    _setClosed();

    if (!immediate) {
      var request = _CancelRequest<T>(this);
      _addRequest(request);
      return request.future;
    }

    if (_isDone && _eventQueue.isEmpty) return Future<void>.value(null);
    return _cancel();
  }

  // ------------------------------------------------------------------
  // Methods that may be called from the request implementations to
  // control the event stream.

  /// Matches events with requests.
  ///
  /// Called after receiving an event or when the event source closes.
  ///
  /// May be called by requests which have returned `false` (saying they
  /// are not yet done) so they can be checked again before any new
  /// events arrive.
  /// Any request returing `false` from `update` when `isDone` is `true`
  /// *must* call `_updateRequests` when they are ready to continue
  /// (since no further events will trigger the call).
  void _updateRequests() {
    while (_requestQueue.isNotEmpty) {
      if (_requestQueue.first.update(_eventQueue, _isDone)) {
        _requestQueue.removeFirst();
      } else {
        return;
      }
    }

    if (!_isDone) {
      _pause();
    }
  }

  // Does nothing by default.
  void _pause() {}

  // ------------------------------------------------------------------
  // Methods called by the event source to add events or say that it's
  // done.

  /// Called when the event source adds a new data or error event.
  /// Always calls [_updateRequests] after adding.
  void _addResult(Result<T> result) {
    _eventsReceived++;
    _eventQueue.add(result);
    _updateRequests();
  }

  /// Called when zero or more events are added.
  /// Always calls [_updateRequests] after adding.
  void _addResults(Queue<Result<T>> results, int start, int end, bool isDone) {
    for (var i = start; i < end; i++) {
      _eventQueue.add(results.elementAt(i));
      _eventsReceived++;
    }
    if (isDone) {
      _close();
    } else {
      _updateRequests();
    }
  }

  /// Called when the event source is done.
  /// Always calls [_updateRequests] after adding.
  void _close() {
    _setDone();
    _updateRequests();
  }

  // ------------------------------------------------------------------
  // Internal helper methods.

  /// Throws an error if [cancel] or [rest] have already been called.
  void _checkNotClosed() {
    if (_isClosed) throw StateError('Already cancelled');
  }

  /// Adds a new request to the queue.
  ///
  /// If the request queue is empty and the request can be completed
  /// immediately, it skips the queue.
  void _addRequest(_EventRequest<T> request) {
    if (_requestQueue.isEmpty) {
      if (request.update(_eventQueue, _isDone)) return;
      _ensureListening();
    }
    _requestQueue.add(request);
  }

  /// Allows subclasses to do something when a first request is added.
  void _ensureListening() {}
}

/// A transaction on a [StreamQueue], created by [StreamQueue.startTransaction].
///
/// Copies of the parent queue may be created using [newQueue]. Calling [commit]
/// moves the parent queue to a copy's position, and calling [reject] causes it
/// to continue as though [StreamQueue.startTransaction] was never called.
class StreamQueueTransaction<T> {
  /// The parent queue on which this transaction is active.
  final StreamQueue<T> _parent;

  /// Queues created using [newQueue].
  final _queues = <StreamQueue<T>>{};

  /// The value -1 until committed or rejected, then then number of consumed
  /// results + 1 for committed and 0 for rejected).
  int _state = -1;

  bool get _active => _state < 0;
  bool get _committed => _state > 0;
  bool get _rejected => _state == 0;

  int get _consumedEvents {
    assert(_state >= 0);
    return _state == 0 ? 0 : _state - 1;
  }

  void _update(Queue<Result<T>> events, bool isDone) {
    if (!_active) return;
    for (var queue in _queues) {
      var start = queue._eventsReceived;
      var end = events.length;
      if (start < end) {
        queue._addResults(events, start, end, isDone);
      } else if (isDone) {
        queue._close();
      }
    }
  }

  StreamQueueTransaction._(this._parent);

  /// Creates a new copy of the parent queue.
  ///
  /// This copy starts at the parent queue's position when
  /// [StreamQueue.startTransaction] was called. Its position can be committed
  /// to the parent queue using [commit].
  StreamQueue<T> newQueue() {
    if (!_active) {
      return StreamQueue._().._flags = StreamQueue._flagDone;
    }
    var queue = StreamQueue<T>._init(_parent._eventQueue, _parent._isDone);
    _queues.add(queue);
    return queue;
  }

  /// Commits a queue created using [newQueue].
  ///
  /// The parent queue's position is updated to be the same as [queue]'s.
  /// Further requests on all queues created by this transaction, including
  /// [queue], will complete as though `cancel` were called with `immediate:
  /// true`.
  ///
  /// Throws a [StateError] if [commit] or [reject] have already been called, or
  /// if there are pending requests on [queue].
  void commit(StreamQueue<T> queue) {
    _assertActive();
    if (!_queues.contains(queue)) {
      throw ArgumentError("Queue doesn't belong to this transaction.");
    } else if (queue._requestQueue.isNotEmpty) {
      throw StateError("A queue with pending requests cannot be committed.");
    }
    _state = queue.eventsDispatched + 1;
    _done();
  }

  /// Rejects this transaction without updating the parent queue.
  ///
  /// The parent will continue as though [StreamQueue.startTransaction] hadn't
  /// been called. Further requests on all queues created by this transaction
  /// will complete as though `cancel` were called with `immediate: true`.
  ///
  /// Throws a [StateError] if [commit] or [reject] have already been called.
  void reject() {
    _assertActive();
    _state = 0;
    _done();
  }

  // Cancels all [_queues], removes the [_TransactionRequest] from [_parent]'s
  // request queue, and runs the next request.
  void _done() {
    for (var queue in _queues) {
      queue._cancel();
    }
    _queues.clear();
    assert(!_active);
    _parent._updateRequests();
  }

  /// Throws a [StateError] if [commit] or [reject] has already been called.
  void _assertActive() {
    if (_active) return;
    if (_rejected) {
      throw StateError('This transaction has already been rejected.');
    } else {
      assert(_committed);
      throw StateError('This transaction has already been accepted.');
    }
  }
}

/// Request object that receives events when they arrive, until fulfilled.
///
/// Each request that cannot be fulfilled immediately is represented by
/// an `_EventRequest` object in the request queue.
///
/// Events from the source stream are sent to the first request in the
/// queue until it reports itself as `isComplete`.
///
/// When the first request in the queue `isComplete`, either when becoming
/// the first request or after receiving an event, its `close` methods is
/// called.
///
/// The `close` method is also called immediately when the source stream
/// is done.
abstract class _EventRequest<T> {
  /// Handle available events.
  ///
  /// The available events are provided as a queue. The `update` function
  /// should only remove events from the front of the event queue, e.g.,
  /// using `removeFirst`.
  ///
  /// Returns `true` if the request is completed, or `false` if it needs
  /// more events.
  /// The call may keep events in the queue until the requeust is complete,
  /// or it may remove them immediately.
  ///
  /// If the method returns true, the request is considered fulfilled, and
  /// will never be called again.
  ///
  /// This method is called when a request reaches the front of the request
  /// queue, and if it returns `false`, it's called again every time a new event
  /// becomes available, or when the stream closes.
  /// If the function returns `false` when the stream has already closed
  /// ([isDone] is true), then the request must call
  /// [StreamQueue._updateRequests] itself when it's ready to continue.
  bool update(Queue<Result<T>> events, bool isDone);
}

/// Request for a [StreamQueue.next] call.
///
/// Completes the returned future when receiving the first event,
/// and is then complete.
class _NextRequest<T> implements _EventRequest<T> {
  /// Completer for the future returned by [StreamQueue.next].
  final _completer = Completer<T>();

  _NextRequest();

  Future<T> get future => _completer.future;

  @override
  bool update(Queue<Result<T>> events, bool isDone) {
    if (events.isNotEmpty) {
      events.removeFirst().complete(_completer);
      return true;
    }
    if (isDone) {
      _completer.completeError(StateError('No elements'), StackTrace.current);
      return true;
    }
    return false;
  }
}

/// Request for a [StreamQueue.peek] call.
///
/// Completes the returned future when receiving the first event,
/// and is then complete, but doesn't consume the event.
class _PeekRequest<T> implements _EventRequest<T> {
  /// Completer for the future returned by [StreamQueue.next].
  final _completer = Completer<T>();

  _PeekRequest();

  Future<T> get future => _completer.future;

  @override
  bool update(Queue<Result<T>> events, bool isDone) {
    if (events.isNotEmpty) {
      events.first.complete(_completer);
      return true;
    }
    if (isDone) {
      _completer.completeError(StateError('No elements'), StackTrace.current);
      return true;
    }
    return false;
  }
}

/// Request for a [StreamQueue.skip] call.
class _SkipRequest<T> implements _EventRequest<T> {
  /// Completer for the future returned by the skip call.
  final _completer = Completer<int>();

  /// Number of remaining events to skip.
  ///
  /// The request `isComplete` when the values reaches zero.
  ///
  /// Decremented when an event is seen.
  /// Set to zero when an error is seen since errors abort the skip request.
  int _eventsToSkip;

  _SkipRequest(this._eventsToSkip);

  /// The future completed when the correct number of events have been skipped.
  Future<int> get future => _completer.future;

  @override
  bool update(Queue<Result<T>> events, bool isDone) {
    while (_eventsToSkip > 0) {
      if (events.isEmpty) {
        if (isDone) break;
        return false;
      }
      _eventsToSkip--;

      var event = events.removeFirst();
      if (event.isError) {
        _completer.completeError(
            event.asError!.error, event.asError!.stackTrace);
        return true;
      }
    }
    _completer.complete(_eventsToSkip);
    return true;
  }
}

/// Common superclass for [_TakeRequest] and [_LookAheadRequest].
abstract class _ListRequest<T> implements _EventRequest<T> {
  /// Completer for the future returned by the take call.
  final _completer = Completer<List<T>>();

  /// List collecting events until enough have been seen.
  final _list = <T>[];

  /// Number of events to capture.
  ///
  /// The request `isComplete` when the length of [_list] reaches
  /// this value.
  final int _eventsToTake;

  _ListRequest(this._eventsToTake);

  /// The future completed when the correct number of events have been captured.
  Future<List<T>> get future => _completer.future;
}

/// Request for a [StreamQueue.take] call.
class _TakeRequest<T> extends _ListRequest<T> {
  _TakeRequest(super.eventsToTake);

  @override
  bool update(Queue<Result<T>> events, bool isDone) {
    while (_list.length < _eventsToTake) {
      if (events.isEmpty) {
        if (isDone) break;
        return false;
      }

      var event = events.removeFirst();
      if (event.isError) {
        event.asError!.complete(_completer);
        return true;
      }
      _list.add(event.asValue!.value);
    }
    _completer.complete(_list);
    return true;
  }
}

/// Request for a [StreamQueue.lookAhead] call.
class _LookAheadRequest<T> extends _ListRequest<T> {
  _LookAheadRequest(super.eventsToTake);

  @override
  bool update(Queue<Result<T>> events, bool isDone) {
    while (_list.length < _eventsToTake) {
      if (events.length == _list.length) {
        if (isDone) break;
        return false;
      }
      var event = events.elementAt(_list.length);
      if (event.isError) {
        event.asError!.complete(_completer);
        return true;
      }
      _list.add(event.asValue!.value);
    }
    _completer.complete(_list);
    return true;
  }
}

/// Request for a [StreamQueue.cancel] call.
///
/// The request needs no events, it just waits in the request queue
/// until all previous events are fulfilled, then it cancels the stream queue
/// source subscription.
class _CancelRequest<T> implements _EventRequest<T> {
  /// Completer for the future returned by the `cancel` call.
  final _completer = Completer<void>();

  /// When the event is completed, it needs to cancel the active subscription
  /// of the `StreamQueue` object, if any.
  final StreamQueue _streamQueue;

  _CancelRequest(this._streamQueue);

  /// The future completed when the cancel request is completed.
  Future get future => _completer.future;

  @override
  bool update(Queue<Result<T>> events, bool isDone) {
    if (isDone) {
      _completer.complete();
    } else {
      _completer.complete(_streamQueue._cancel()); // ignore: void_checks
    }
    return true;
  }
}

/// Request for a [StreamQueue.rest] call.
///
/// The request is always complete, it just waits in the request queue
/// until all previous events are fulfilled, then it takes over the
/// stream events subscription and creates a stream from it.
class _StreamRestRequest<T> implements _EventRequest<T> {
  /// Completer for the stream returned by the `rest` call.
  final _completer = StreamCompleter<T>();

  /// The [StreamQueue] object that has this request queued.
  ///
  /// When the event is completed, it needs to cancel the active subscription
  /// of the `StreamQueue` object, if any.
  final _StreamStreamQueue<T> _streamQueue;

  _StreamRestRequest(this._streamQueue);

  /// The stream which will contain the remaining events of [_streamQueue].
  Stream<T> get stream => _completer.stream;

  @override
  bool update(Queue<Result<T>> events, bool isDone) {
    if (events.isEmpty) {
      if (_streamQueue._isDone) {
        _completer.setEmpty();
      } else {
        _completer.setSourceStream(_streamQueue._extractStream());
      }
    } else {
      // There are prefetched events which needs to be added before the
      // remaining stream.
      var controller = StreamController<T>(sync: true);
      for (var event in events) {
        event.addTo(controller);
      }
      controller
          .addStream(_streamQueue._extractStream(), cancelOnError: false)
          .whenComplete(controller.close);
      _completer.setSourceStream(controller.stream);
    }
    return true;
  }
}

/// Request for a [StreamQueue.rest] call.
///
/// The request is always complete, it just waits in the request queue
/// until all previous events are fulfilled, then it takes over the
/// stream events subscription and creates a stream from it.
class _RestRequest<T> implements _EventRequest<T> {
  _RestRequest();

  final StreamController<T> _controller = StreamController<T>(sync: true);

  /// The stream which will contain the remaining events.
  Stream<T> get stream => _controller.stream;

  @override
  bool update(Queue<Result<T>> events, bool isDone) {
    while (events.isNotEmpty) {
      events.removeFirst().addTo(_controller);
    }
    if (isDone) {
      _controller.close();
      return true;
    }
    return false;
  }
}

/// Request for a [StreamQueue.hasNext] call.
///
/// Completes the [future] with `true` if it sees any event,
/// but doesn't consume the event.
/// If the request is closed without seeing an event, then
/// the [future] is completed with `false`.
class _HasNextRequest<T> implements _EventRequest<T> {
  final _completer = Completer<bool>();

  Future<bool> get future => _completer.future;

  @override
  bool update(Queue<Result<T>> events, bool isDone) {
    if (events.isNotEmpty) {
      _completer.complete(true);
      return true;
    }
    if (isDone) {
      _completer.complete(false);
      return true;
    }
    return false;
  }
}

/// Request for a [StreamQueue.startTransaction] call.
///
/// This request isn't complete until the user calls
/// [StreamQueueTransaction.commit] or [StreamQueueTransaction.reject], at which
/// point it manually removes itself from the request queue and calls
/// [StreamQueue._updateRequests].
class _TransactionRequest<T> implements _EventRequest<T> {
  /// The transaction created by this request.
  final StreamQueueTransaction<T> transaction;

  int eventsProvided = 0;

  _TransactionRequest(StreamQueue<T> parent)
      : transaction = StreamQueueTransaction._(parent);

  @override
  bool update(Queue<Result<T>> events, bool isDone) {
    // The transaction never updates the events.
    // It forwards events to transaction queues,
    // and we check whether the transaction has been commmitted or not,
    // and remove consumed events here before returning true.
    transaction._update(events, isDone);
    if (transaction._active) return false;
    // Is committed or rejected. If committed, consumed events may be positive.
    var consumedEvents = transaction._consumedEvents;
    for (var i = 0; i < consumedEvents; i++) {
      events.removeFirst();
    }
    return true;
  }
}
