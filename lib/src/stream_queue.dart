// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:collection';

import 'package:collection/collection.dart';

import "result.dart";
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
///     var events = new StreamQueue<String>(someStreamOfLines);
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
abstract class StreamQueue<T> {
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

  /// Whether the event source is done.
  bool _isDone = false;

  /// Whether a closing operation has been performed on the stream queue.
  ///
  /// Closing operations are [cancel] and [rest].
  bool _isClosed = false;

  /// Queue of events not used by a request yet.
  final QueueList<Result> _eventQueue = new QueueList();

  /// Queue of pending requests.
  ///
  /// Access through methods below to ensure consistency.
  final Queue<_EventRequest> _requestQueue = new Queue();

  /// Create a `StreamQueue` of the events of [source].
  factory StreamQueue(Stream<T> source) = _StreamQueue<T>;

  StreamQueue._();

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
      var hasNextRequest = new _HasNextRequest();
      _addRequest(hasNextRequest);
      return hasNextRequest.future;
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
      var nextRequest = new _NextRequest<T>();
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
    var request = new _RestRequest<T>(this);
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
    if (count < 0) throw new RangeError.range(count, 0, null, "count");
    if (!_isClosed) {
      var request = new _SkipRequest(count);
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
    if (count < 0) throw new RangeError.range(count, 0, null, "count");
    if (!_isClosed) {
      var request = new _TakeRequest<T>(count);
      _addRequest(request);
      return request.future;
    }
    throw _failClosed();
  }

  /// Requests a batch of [count] connected "transactions" that can
  /// conditionally consume events.
  ///
  /// Each transaction is a [TransactionStreamQueue] which acts as an
  /// independent clone of this queue, starting from this queue's current state.
  /// They can be used to inspect upcoming events without changing the state of
  /// the this queue. To do so, transactions have two methods in addition to the
  /// [StreamQueue] interface:
  ///
  /// * [TransactionStreamQueue.reject] marks the transaction as finished
  ///   without changing the state of this queue.
  ///
  /// * [TransactionStreamQueue.accept] updates this queue with the state of the
  ///   transaction. Only one transaction in a batch may be accepted—the others
  ///   are automatically rejected.
  ///
  /// As long as any transactions in the batch are active, this queue won't emit
  /// any events. If a transaction is accepted, this will move past any events
  /// that transaction consumed. If all transactions are rejected, this will
  /// continue from the same point [startTransactions] was called.
  ///
  /// ```dart
  /// /// Consumes all empty lines from the beginning of [lines].
  /// Future consumeEmptyLines(StreamQueue<String> lines) {
  ///   while (await lines.hasNext) {
  ///     var transaction = lines.startTransaction();
  ///     if ((await transaction.next).isNotEmpty) {
  ///       transaction.reject();
  ///       return;
  ///     } else {
  ///       transaction.accept();
  ///     }
  ///   }
  /// }
  /// ```
  List<TransactionStreamQueue> startTransactions(int count) {
    if (count < 0) throw new RangeError.range(count, 0, null, "count");
    if (_isClosed) throw _failClosed();

    var request = new _TransactionRequest(this, count);
    _addRequest(request);
    return request.transactions;
  }

  /// A utility method for starting a single transaction using
  /// [startTransactions].
  TransactionStreamQueue startTransaction() => startTransactions(1).first;

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
  /// None of [next], [rest], [skip], [take] or [cancel] may be
  /// called again.
  Future cancel({bool immediate: false}) {
    if (_isClosed) throw _failClosed();
    _isClosed = true;

    if (!immediate) {
      var request = new _CancelRequest(this);
      _addRequest(request);
      return request.future;
    }

    if (_isDone && _eventQueue.isEmpty) return new Future.value();
    return _cancel();
  }

  // ------------------------------------------------------------------
  // Methods that may be called from the request implementations to
  // control the even stream.

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
  Stream<T> _extractStream();

  /// Requests that the event source pauses events.
  ///
  /// This is called automatically when the request queue is empty.
  ///
  /// The event source is restarted by the next call to [_ensureListening].
  void _pause();

  /// Ensures that we are listening on events from the event source.
  ///
  /// Starts listening for the first time or resumes after a [_pause].
  ///
  /// Is called automatically if a request requires more events.
  void _ensureListening();

  /// Cancels the underlying event source.
  Future _cancel();

  // ------------------------------------------------------------------
  // Methods called by the event source to add events or say that it's
  // done.

  /// Called when the event source adds a new data or error event.
  /// Always calls [_updateRequests] after adding.
  void _addResult(Result result) {
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
    return new StateError("Already cancelled");
  }

  /// Adds a new request to the queue.
  ///
  /// If the request queue is empty and the request can be completed
  /// immediately, it skips the queue.
  void _addRequest(_EventRequest request) {
    if (_requestQueue.isEmpty) {
      if (request.update(_eventQueue, _isDone)) return;
      _ensureListening();
    }
    _requestQueue.add(request);
  }
}


/// The default implementation of [StreamQueue].
///
/// This queue gets its events from a stream which is listened
/// to when a request needs events.
class _StreamQueue<T> extends StreamQueue<T> {
  /// Source of events.
  final Stream<T> _sourceStream;

  /// Subscription on [_sourceStream] while listening for events.
  ///
  /// Set to subscription when listening, and set to `null` when the
  /// subscription is done (and [_isDone] is set to true).
  StreamSubscription<T> _subscription;

  _StreamQueue(this._sourceStream) : super._();

  Future _cancel() {
    if (_isDone) return null;
    if (_subscription == null) _subscription = _sourceStream.listen(null);
    var future = _subscription.cancel();
    _close();
    return future;
  }

  void _ensureListening() {
    if (_isDone) return;
    if (_subscription == null) {
      _subscription =
          _sourceStream.listen(
              (data) {
                _addResult(new Result.value(data));
              },
              onError: (error, StackTrace stackTrace) {
                _addResult(new Result.error(error, stackTrace));
              },
              onDone: () {
                _subscription = null;
                this._close();
              });
    } else {
      _subscription.resume();
    }
  }

  void _pause() {
    _subscription.pause();
  }

  Stream<T> _extractStream() {
    assert(_isClosed);
    if (_isDone) {
      return new Stream<T>.empty();
    }

    if (_subscription == null) {
      return _sourceStream;
    }

    var subscription = _subscription;
    _subscription = null;
    _isDone = true;

    var wasPaused = subscription.isPaused;
    var result = new SubscriptionStream<T>(subscription);
    // Resume after creating stream because that pauses the subscription too.
    // This way there won't be a short resumption in the middle.
    if (wasPaused) subscription.resume();
    return result;
  }
}

/// A [StreamQueue] cloned from a parent by [StreamQueue.startTransactions].
///
/// This queue may be [accept]ed, moving the parent to the same event as this,
/// or [reject]ed, marking this as finished without modifying the parent.
class TransactionStreamQueue<T> extends _StreamQueue<T> {
  /// The request that created this queue.
  final _TransactionRequest<T> _request;

  /// Whether [accept] has been called.
  var _accepted = false;

  /// Whether [reject] has been called.
  var _rejected = false;

  /// The total number of events received by this queue, including events that
  /// haven't yet been consumed by requests.
  ///
  /// This is used to fast-forward the parent queue if this transaction is
  /// accepted.
  var _eventsReceived = 0;

  TransactionStreamQueue._(Stream<T> sourceStream, this._request)
      : super(sourceStream);

  /// Updates the parent [StreamQueue] to match this transaction's state.
  ///
  /// Further requests on this queue will be completed as though the underlying
  /// stream had been closed, as though [cancel] were called with `immediate:
  /// true`. Other transactions in the same batch are automatically rejected.
  ///
  /// Throws a [StateError] if [accept] or [reject] has already been called, or
  /// if there are pending requests on this queue.
  void accept() {
    _assertActive();

    if (_requestQueue.isNotEmpty) {
      throw new StateError(
          "A transaction with pending requests can't be accepted.");
    }

    _accepted = true;
    _cancel();
    _request._onAccept(this);
  }

  /// Closes this transaction without updating the parent [StreamQueue].
  ///
  /// If all transactions in a batch are rejected, the parent will continue from
  /// its state when [startTransactions] was called.
  ///
  /// Further requests and pending requests on this queue will be completed as
  /// though the underlying stream had been closed, as though [cancel] were
  /// called with `immediate: true`.
  ///
  /// Throws a [StateError] if [accept] or [reject] has already been called.
  void reject() {
    _assertActive();
    _rejected = true;
    _cancel();
    _request._onReject();
  }

  /// Throws a [StateError] if [accept] or [reject] has already been called.
  void _assertActive() {
    if (_accepted) {
      throw new StateError("This transaction has already been accepted.");
    } else if (_rejected) {
      throw new StateError("This transaction has already been rejected.");
    }
  }

  /// Modifies [StreamQueue._addResult] to count the total number of events that
  /// have been passed to this transaction.
  void _addResult(Result result) {
    _eventsReceived++;
    super._addResult(result);
  }
}

/// Request object that receives events when they arrive, until fulfilled.
///
/// Each request that cannot be fulfilled immediately is represented by
/// an `_EventRequest` object in the request queue.
///
/// Events from the source stream are sent to the first request in the
/// queue until it reports itself as [isComplete].
///
/// When the first request in the queue `isComplete`, either when becoming
/// the first request or after receiving an event, its [close] methods is
/// called.
///
/// The [close] method is also called immediately when the source stream
/// is done.
abstract class _EventRequest<T> {
  /// Handle available events.
  ///
  /// The available events are provided as a queue. The `update` function
  /// should only remove events from the front of the event queue, e.g.,
  /// using [removeFirst].
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
  bool update(QueueList<Result<T>> events, bool isDone);
}

/// Request for a [StreamQueue.next] call.
///
/// Completes the returned future when receiving the first event,
/// and is then complete.
class _NextRequest<T> implements _EventRequest<T> {
  /// Completer for the future returned by [StreamQueue.next].
  final _completer = new Completer<T>();

  _NextRequest();

  Future<T> get future => _completer.future;

  bool update(QueueList<Result<T>> events, bool isDone) {
    if (events.isNotEmpty) {
      events.removeFirst().complete(_completer);
      return true;
    }
    if (isDone) {
      var errorFuture =
          new Future.sync(() => throw new StateError("No elements"));
      _completer.complete(errorFuture);
      return true;
    }
    return false;
  }
}

/// Request for a [StreamQueue.skip] call.
class _SkipRequest<T> implements _EventRequest<T> {
  /// Completer for the future returned by the skip call.
  final _completer = new Completer<int>();

  /// Number of remaining events to skip.
  ///
  /// The request [isComplete] when the values reaches zero.
  ///
  /// Decremented when an event is seen.
  /// Set to zero when an error is seen since errors abort the skip request.
  int _eventsToSkip;

  _SkipRequest(this._eventsToSkip);

  /// The future completed when the correct number of events have been skipped.
  Future<int> get future => _completer.future;

  bool update(QueueList<Result<T>> events, bool isDone) {
    while (_eventsToSkip > 0) {
      if (events.isEmpty) {
        if (isDone) break;
        return false;
      }
      _eventsToSkip--;

      var event = events.removeFirst();
      if (event.isError) {
        _completer.completeError(event.asError.error, event.asError.stackTrace);
        return true;
      }
    }
    _completer.complete(_eventsToSkip);
    return true;
  }
}

/// Request for a [StreamQueue.take] call.
class _TakeRequest<T> implements _EventRequest<T> {
  /// Completer for the future returned by the take call.
  final _completer = new Completer<List<T>>();

  /// List collecting events until enough have been seen.
  final _list = <T>[];

  /// Number of events to capture.
  ///
  /// The request [isComplete] when the length of [_list] reaches
  /// this value.
  final int _eventsToTake;

  _TakeRequest(this._eventsToTake);

  /// The future completed when the correct number of events have been captured.
  Future<List<T>> get future => _completer.future;

  bool update(QueueList<Result<T>> events, bool isDone) {
    while (_list.length < _eventsToTake) {
      if (events.isEmpty) {
        if (isDone) break;
        return false;
      }

      var event = events.removeFirst();
      if (event.isError) {
        _completer.completeError(event.asError.error, event.asError.stackTrace);
        return true;
      }
      _list.add(event.asValue.value);
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
  final _completer = new Completer();
  ///
  /// When the event is completed, it needs to cancel the active subscription
  /// of the `StreamQueue` object, if any.
  final StreamQueue _streamQueue;

  _CancelRequest(this._streamQueue);

  /// The future completed when the cancel request is completed.
  Future get future => _completer.future;

  bool update(QueueList<Result<T>> events, bool isDone) {
    if (_streamQueue._isDone) {
      _completer.complete();
    } else {
      _streamQueue._ensureListening();
      _completer.complete(_streamQueue._extractStream().listen(null).cancel());
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
  /// Completer for the stream returned by the `rest` call.
  final _completer = new StreamCompleter<T>();

  /// The [StreamQueue] object that has this request queued.
  ///
  /// When the event is completed, it needs to cancel the active subscription
  /// of the `StreamQueue` object, if any.
  final StreamQueue<T> _streamQueue;

  _RestRequest(this._streamQueue);

  /// The stream which will contain the remaining events of [_streamQueue].
  Stream<T> get stream => _completer.stream;

  bool update(QueueList<Result<T>> events, bool isDone) {
    if (events.isEmpty) {
      if (_streamQueue._isDone) {
        _completer.setEmpty();
      } else {
        _completer.setSourceStream(_streamQueue._extractStream());
      }
    } else {
      // There are prefetched events which needs to be added before the
      // remaining stream.
      var controller = new StreamController<T>();
      for (var event in events) {
        event.addTo(controller);
      }
      controller.addStream(_streamQueue._extractStream(), cancelOnError: false)
                .whenComplete(controller.close);
      _completer.setSourceStream(controller.stream);
    }
    return true;
  }
}

/// Request for a [StreamQueue.hasNext] call.
///
/// Completes the [future] with `true` if it sees any event,
/// but doesn't consume the event.
/// If the request is closed without seeing an event, then
/// the [future] is completed with `false`.
class _HasNextRequest<T> implements _EventRequest<T> {
  final _completer = new Completer<bool>();

  Future<bool> get future => _completer.future;

  bool update(QueueList<Result<T>> events, bool isDone) {
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

/// Request for a [StreamQueue.startTransactions] call.
///
/// The request isn't complete until the user calls
/// [TransactionStreamQueue.accept] or [TransactionStreamQueue.reject] on one of
/// the transactions, at which point it manually removes itself from the request
/// queue and calls [StreamQueue._updateRequests].
class _TransactionRequest<T> implements _EventRequest<T> {
  /// The batch of transactions for this request.
  final List<TransactionStreamQueue<T>> transactions;

  /// The stream queue to which this request was made.
  final StreamQueue<T> _parent;

  /// The controller that passes events to [transactions].
  final _controller = new StreamController<T>(sync: true);

  /// The number of events passed to [_controller] so far.
  var _eventsSent = 0;

  /// The number of transactions that have been rejected so far.
  var _rejections = 0;

  _TransactionRequest(this._parent, int count)
      : transactions = new List(count) {
    var splitter = new StreamSplitter(_controller.stream);
    for (var i = 0; i < count; i++) {
      transactions[i] = new TransactionStreamQueue._(splitter.split(), this);
    }
    splitter.close();
  }

  bool update(QueueList<Result<T>> events, bool isDone) {
    while (_eventsSent < events.length) {
      var result = events[_eventsSent++];
      if (result.isValue) {
        _controller.add(result.asValue.value);
      } else {
        _controller.addError(result.asError.error, result.asError.stackTrace);
      }
    }
    if (isDone && !_controller.isClosed) _controller.close();
    return false;
  }

  /// Called when [transaction] is accepted.
  ///
  /// Updates [_parent] to have the same state as [transaction] and rejects all
  /// other transactions in [transactions].
  void _onAccept(TransactionStreamQueue<T> transaction) {
    // Remove all events from the parent queue that were consumed by the
    // child queue.
    var eventsConsumed =
        transaction._eventsReceived - transaction._eventQueue.length;
    for (var j = 0; j < eventsConsumed; j++) {
      _parent._eventQueue.removeFirst();
    }

    // Mark other transactions as rejected.
    for (var otherQueue in transactions) {
      if (otherQueue == transaction) continue;
      if (otherQueue._rejected) continue;
      otherQueue._rejected = true;
      otherQueue._cancel();
    }

    // Remove this transaction and re-runs the parent queue.
    assert(transaction._requestQueue.isEmpty);
    assert(_parent._requestQueue.first == this);
    _parent._requestQueue.removeFirst();
    _parent._updateRequests();
  }

  /// Called when a transaction is rejected.
  ///
  /// If all transactions have been rejected, makes [_parent] continue
  /// processing requests after this one.
  void _onReject() {
    _rejections++;
    if (_rejections != transactions.length) return;

    // If all transactions have been rejected, this request matches no
    // events. Remove it and re-run the queue.
    assert(_parent._requestQueue.first == this);
    _parent._requestQueue.removeFirst();
    _parent._updateRequests();
  }
}
