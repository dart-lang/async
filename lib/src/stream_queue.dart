// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';

import 'package:collection/collection.dart';

import "cancelable_operation.dart";
import "result/result.dart";
import "subscription_stream.dart";
import "stream_completer.dart";
import "stream_splitter.dart";

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

  final Stream<T> _source;

  /// Subscription on [_source] while listening for events.
  ///
  /// Set to subscription when listening, and set to `null` when the
  /// subscription is done (and [_isDone] is set to true).
  StreamSubscription<T> _subscription;

  /// Whether the event source is done.
  bool _isDone = false;

  /// Whether a closing operation has been performed on the stream queue.
  ///
  /// Closing operations are [cancel] and [rest].
  bool _isClosed = false;

  /// The number of events dispatched by this queue.
  ///
  /// This counts error events. It doesn't count done events, or events
  /// dispatched to a stream returned by [rest].
  int get eventsDispatched => _eventsReceived - _eventQueue.length;

  /// The number of events received by this queue.
  var _eventsReceived = 0;

  /// Queue of events not used by a request yet.
  final QueueList<Result<T>> _eventQueue = QueueList();

  /// Queue of pending requests.
  ///
  /// Access through methods below to ensure consistency.
  final Queue<_EventRequest> _requestQueue = Queue();

  /// Create a `StreamQueue` of the events of [source].
  factory StreamQueue(Stream<T> source) => StreamQueue._(source);

  // Private generative constructor to avoid subclasses.
  StreamQueue._(this._source);

  /// Asks if the stream has any more events.
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
    if (!_isClosed) {
      var hasNextRequest = _HasNextRequest<T>();
      _addRequest(hasNextRequest);
      return hasNextRequest.future;
    }
    throw _failClosed();
  }

  /// Look at the next [count] data events without consuming them.
  ///
  /// Works like [take] except that the events are left in the queue.
  /// If one of the next [count] events is an error, the returned future
  /// completes with this error, and the error is still left in the queue.
  Future<List<T>> lookAhead(int count) {
    if (count < 0) throw RangeError.range(count, 0, null, "count");
    if (!_isClosed) {
      var request = _LookAheadRequest<T>(count);
      _addRequest(request);
      return request.future;
    }
    throw _failClosed();
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
    if (!_isClosed) {
      var nextRequest = _NextRequest<T>();
      _addRequest(nextRequest);
      return nextRequest.future;
    }
    throw _failClosed();
  }

  /// Looks at the next (yet unrequested) event from the stream.
  ///
  /// Like [next] except that the event is not consumed.
  /// If the next event is an error event, it stays in the queue.
  Future<T> get peek {
    if (!_isClosed) {
      var nextRequest = _PeekRequest<T>();
      _addRequest(nextRequest);
      return nextRequest.future;
    }
    throw _failClosed();
  }

  /// Returns a stream of all the remaning events of the source stream.
  ///
  /// All requested [next], [skip] or [take] operations are completed
  /// first, and then any remaining events are provided as events of
  /// the returned stream.
  ///
  /// Using `rest` closes this stream queue. After getting the
  /// `rest` the caller may no longer request other events, like
  /// after calling [cancel].
  Stream<T> get rest {
    if (_isClosed) {
      throw _failClosed();
    }
    var request = _RestRequest<T>(this);
    _isClosed = true;
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
    if (count < 0) throw RangeError.range(count, 0, null, "count");
    if (!_isClosed) {
      var request = _SkipRequest<T>(count);
      _addRequest(request);
      return request.future;
    }
    throw _failClosed();
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
    if (count < 0) throw RangeError.range(count, 0, null, "count");
    if (!_isClosed) {
      var request = _TakeRequest<T>(count);
      _addRequest(request);
      return request.future;
    }
    throw _failClosed();
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
  /// Future consumeEmptyLines(StreamQueue<String> lines) async {
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
    if (_isClosed) throw _failClosed();

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
  /// Future consumeEmptyLines(StreamQueue<String> lines) async {
  ///   while (await lines.hasNext) {
  ///     // Consume a line if it's empty, otherwise return.
  ///     if (!await lines.withTransaction(
  ///         (queue) async => (await queue.next).isEmpty)) {
  ///       return;
  ///     }
  ///   }
  /// }
  /// ```
  Future<bool> withTransaction(Future<bool> callback(StreamQueue<T> queue)) {
    var transaction = startTransaction();

    /// Avoid async/await to ensure that [startTransaction] is called
    /// synchronously and so ends up in the right place in the request queue.
    var queue = transaction.newQueue();
    return callback(queue).then((result) {
      if (result) {
        transaction.commit(queue);
      } else {
        transaction.reject();
      }
      return result;
    }, onError: (error) {
      transaction.commit(queue);
      throw error;
    });
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
      Future<S> callback(StreamQueue<T> queue)) {
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
  /// immediately. Any pending events are completed as though the underlying
  /// stream had closed.
  ///
  /// The returned future completes with the result of calling
  /// `cancel`.
  ///
  /// After calling `cancel`, no further events can be requested.
  /// None of [lookAhead], [next], [peek], [rest], [skip], [take] or [cancel]
  /// may be called again.
  Future cancel({bool immediate = false}) {
    if (_isClosed) throw _failClosed();
    _isClosed = true;

    if (!immediate) {
      var request = _CancelRequest<T>(this);
      _addRequest(request);
      return request.future;
    }

    if (_isDone && _eventQueue.isEmpty) return Future.value();
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
    _isDone = true;

    if (_subscription == null) {
      return _source;
    }

    var subscription = _subscription;
    _subscription = null;

    var wasPaused = subscription.isPaused;
    var result = SubscriptionStream<T>(subscription);
    // Resume after creating stream because that pauses the subscription too.
    // This way there won't be a short resumption in the middle.
    if (wasPaused) subscription.resume();
    return result;
  }

  /// Requests that the event source pauses events.
  ///
  /// This is called automatically when the request queue is empty.
  ///
  /// The event source is restarted by the next call to [_ensureListening].
  void _pause() {
    _subscription.pause();
  }

  /// Ensures that we are listening on events from the event source.
  ///new
  /// Starts listening for the first time or resumes after a [_pause].
  ///
  /// Is called automatically if a request requires more events.
  void _ensureListening() {
    if (_isDone) return;
    if (_subscription == null) {
      _subscription = _source.listen((data) {
        _addResult(Result.value(data));
      }, onError: (error, StackTrace stackTrace) {
        _addResult(Result.error(error, stackTrace));
      }, onDone: () {
        _subscription = null;
        this._close();
      });
    } else {
      _subscription.resume();
    }
  }

  /// Cancels the underlying event source.
  Future _cancel() {
    if (_isDone) return null;
    _subscription ??= _source.listen(null);
    var future = _subscription.cancel();
    _close();
    return future;
  }

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

  /// Called when the event source is done.
  /// Always calls [_updateRequests] after adding.
  void _close() {
    _isDone = true;
    _updateRequests();
  }

  // ------------------------------------------------------------------
  // Internal helper methods.

  /// Returns an error for when a request is made after cancel.
  ///
  /// Returns a [StateError] with a message saying that either
  /// [cancel] or [rest] have already been called.
  Error _failClosed() {
    return StateError("Already cancelled");
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
}
