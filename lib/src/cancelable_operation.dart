// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

/// An asynchronous operation that can be cancelled.
///
/// The value of this operation is exposed as [value]. When this operation is
/// cancelled, [value] won't complete either successfully or with an error. If
/// [value] has already completed, cancelling the operation does nothing.
class CancelableOperation<T> {
  /// The completer that produced this operation.
  ///
  /// That completer is canceled when [cancel] is called.
  final CancelableCompleter<T> _completer;

  CancelableOperation._(this._completer);

  /// Creates a [CancelableOperation] with the same result as the [result] future.
  ///
  /// When this operation is canceled, [onCancel] will be called and any value
  /// or error later produced by [result] will be discarded.
  /// If [onCancel] returns a [Future], it will be returned by [cancel].
  ///
  /// The [onCancel] funcion will be called synchronously
  /// when the new operation is canceled, and will be called at most once.\
  ///
  /// Calling this constructor is equivalent to creating a
  /// [CancelableCompleter] and completing it with [result].
  factory CancelableOperation.fromFuture(Future<T> result,
          {FutureOr Function()? onCancel}) =>
      (CancelableCompleter<T>(onCancel: onCancel)..complete(result)).operation;

  /// Creates a [CancelableOperation] wrapping [subscription].
  ///
  /// This overrides [subscription.onDone] and [subscription.onError] so that
  /// the returned operation will complete when the subscription completes or
  /// emits an error. When this operation is canceled or when it emits an error,
  /// the subscription will be canceled (unlike
  /// `CancelableOperation.fromFuture(subscription.asFuture())`).
  static CancelableOperation<void> fromSubscription(
      StreamSubscription<void> subscription) {
    var completer = CancelableCompleter<void>(onCancel: subscription.cancel);
    subscription.onDone(completer.complete);
    subscription.onError((Object error, StackTrace stackTrace) {
      subscription.cancel().whenComplete(() {
        completer.completeError(error, stackTrace);
      });
    });
    return completer.operation;
  }

  /// Creates a [CancelableOperation] that completes with the value of the first
  /// of [operations] to complete.
  ///
  /// Once any of [operations] completes, its result is forwarded to the
  /// new [CancelableOperation] and the rest are cancelled. If the
  /// bew operation is cancelled, all the [operations] are cancelled as
  /// well.
  static CancelableOperation<T> race<T>(
      Iterable<CancelableOperation<T>> operations) {
    operations = operations.toList();
    if (operations.isEmpty) {
      throw ArgumentError("May not be empty", "operations");
    }

    var done = false;
    // Note: if one or more of the completers have already completed,
    // they're not actually cancelled by this.
    Future<void> _cancelAll() {
      done = true;
      return Future.wait(operations.map((operation) => operation.cancel()));
    }

    var completer = CancelableCompleter<T>(onCancel: _cancelAll);
    for (var operation in operations) {
      operation.then((value) {
        if (!done) _cancelAll().whenComplete(() => completer.complete(value));
      }, onError: (error, stackTrace) {
        if (!done) {
          _cancelAll()
              .whenComplete(() => completer.completeError(error, stackTrace));
        }
      });
    }

    return completer.operation;
  }

  /// The result of this operation, if not cancelled.
  ///
  /// This future will not complete if the operation is cancelled.
  /// Use [valueOrCancellation] for a future which completes
  /// both if the operation is cancelled and if it isn't.
  Future<T> get value => _completer._inner.future;

  /// Creates a [Stream] containing the result of this operation.
  ///
  /// This is like `value.asStream()`, but if a subscription to the stream is
  /// canceled, this operation is as well.
  Stream<T> asStream() {
    var controller =
        StreamController<T>(sync: true, onCancel: _completer._cancel);

    value.then((value) {
      controller.add(value);
      controller.close();
    }, onError: (Object error, StackTrace stackTrace) {
      controller.addError(error, stackTrace);
      controller.close();
    });
    return controller.stream;
  }

  /// Creates a [Future] that completes when this operation completes *or* when
  /// it's cancelled.
  ///
  /// If this operation completes, this completes to the same result as [value].
  /// If this operation is cancelled, the returned future waits for the future
  /// returned by [cancel], then completes to [cancellationValue].
  Future<T?> valueOrCancellation([T? cancellationValue]) {
    var completer = Completer<T?>.sync();
    value.then(completer.complete, onError: completer.completeError);

    _completer._cancelCompleter.future.then((_) {
      completer.complete(cancellationValue);
    }, onError: completer.completeError);

    return completer.future;
  }

  /// Creates a new cancelable operation to be completed
  /// when this operation completes or is cancelled.
  ///
  /// The [onValue] and [onError] callbacks behave in the same way as
  /// for [Future.then], and the result of those callbacks is used to complete
  /// the returned cancelable operation.
  ///
  /// If [onCancel] is provided, and the this operation is canceled,
  /// the [onCancel] callback is called and the returned operation completes
  /// with the result returned by that call.
  ///
  /// If [onCancel] is not provided, and this operation is canceled, then the
  /// returned operation is also canceled.
  ///
  /// If [propagateCancel] is `true` and the returned operation is canceled
  /// then this operation is canceled. The default is `false`.
  CancelableOperation<R> then<R>(FutureOr<R> Function(T) onValue,
      {FutureOr<R> Function(Object, StackTrace)? onError,
      FutureOr<R> Function()? onCancel,
      bool propagateCancel = false}) {
    final completer =
        CancelableCompleter<R>(onCancel: propagateCancel ? cancel : null);

    if (!isCanceled) {
      value
          .then(onValue, onError: onError)
          .then(completer.complete, onError: completer.completeError);
    }
    _completer._cancelCompleter.future.then((_) {
      if (onCancel != null) {
        completer.complete(Future.sync(onCancel));
      } else {
        completer._cancel();
      }
    });

    return completer.operation;
  }

  /// Cancels this operation.
  ///
  /// If this operation [isComplete] or [isCanceled] this call is ignored.
  /// Returns the result of the `onCancel` callback, if one exists.
  Future cancel() => _completer._cancel();

  /// Whether this operation has been canceled before it completed.
  bool get isCanceled => _completer.isCanceled;

  /// Whether the result of this operation is ready.
  ///
  /// When ready, the [value] future is completed with the result value
  /// or error, and this operation can no longer be cancelled.
  /// An operation may be complete before the listeners on [value] are invoked.
  bool get isCompleted => _completer._inner.isCompleted;
}

/// A completer for a [CancelableOperation].
class CancelableCompleter<T> {
  /// The completer for the wrapped future.
  ///
  /// At most one of `_inner.future` and `_cancelCompleter.future` will
  /// ever complete.
  final _inner = Completer<T>();

  /// Completed when `cancel` is called.
  ///
  /// At most one of `_inner.future` and `_cancelCompleter.future` will
  /// ever complete.
  final _cancelCompleter = Completer<void>();

  /// The callback to call if the operation is canceled.
  final FutureOr<void> Function()? _onCancel;

  /// The operation controlled by this completer.
  late final operation = CancelableOperation<T>._(this);

  /// Set when [complete] or [completeError] is called.
  ///
  /// Completing twice is not allowed.
  ///
  /// If [complete] is called with a future, it's still possible to
  /// cancel the operation until that future completes,
  /// so this value and [_isCanceled] are not mutually exclusive.
  bool _isCompleted = false;

  /// Set when [cancel] is called.
  ///
  /// Cancelling twice does nothing, nor does completing after cancelling.
  bool _isCanceled = false;

  /// Creates a new completer for a [CancelableOperation].
  ///
  /// The cancelable [operation] can be completed using
  /// [complete] or [completeError].
  ///
  /// The [onCancel] function is called if the [operation] is canceled,
  /// by calling [CancelableOperation.cancel]
  /// before the operation has completed.
  /// If [onCancel] returns a [Future],
  /// that future is also returned by [CancelableOperation.cancel].
  ///
  /// The [onCancel] function will be called at most once.
  CancelableCompleter({FutureOr Function()? onCancel}) : _onCancel = onCancel;

  /// Whether the [complete] or [completeError] have been called.
  ///
  /// Once this completer has been completed with either a result or error,
  /// neither method may be called again.
  ///
  /// If [complete] was called with a [Future] argument, this completer may be
  /// completed before it's [operation] is completed. In that case the
  /// [operation] may still be canceled before the result is available.
  bool get isCompleted => _isCompleted;

  /// Whether the completer was canceled before the result was ready.
  bool get isCanceled => _isCanceled;

  /// Completes [operation] with [value].
  ///
  /// If [value] is a [Future] the [operation] will complete
  /// with the result of that `Future` once it is available.
  /// In that case [isComplete] will be `true` before the [operation]
  /// is complete.
  ///
  /// If the type [T] is not nullable [value] may be not be omitted or `null`.
  ///
  /// This method may not be called after either [complete] or [completeError]
  /// has been called once.
  /// The [isCompleted] is true when either of these methods have been called.
  void complete([FutureOr<T>? value]) {
    if (_isCompleted) throw StateError('Operation already completed');
    _isCompleted = true;

    if (value is! Future<T>) {
      if (_isCanceled) return;
      _inner.complete(value);
      return;
    }

    if (_isCanceled) {
      // Make sure errors from [value] aren't top-leveled.
      value.ignore();
      return;
    }

    value.then((result) {
      if (_isCanceled) return;
      _inner.complete(result);
    }, onError: (Object error, StackTrace stackTrace) {
      if (_isCanceled) return;
      _inner.completeError(error, stackTrace);
    });
  }

  /// Completes [operation] with [error] and [stackTrace].
  ///
  /// This method may not be called after either [complete] or [completeError]
  /// has been called once.
  /// The [isCompleted] is true when either of these methods have been called.
  void completeError(Object error, [StackTrace? stackTrace]) {
    if (_isCompleted) throw StateError('Operation already completed');
    _isCompleted = true;

    if (_isCanceled) return;
    _inner.completeError(error, stackTrace);
  }

  /// Cancels the operation.
  ///
  /// If the operation has already completed, prior to being cancelled,
  /// this method does nothing.
  /// If the operation has already been cancelled, this method returns
  /// the same result as the first call to `_cancel`.
  ///
  /// The result of the operation may only be available some time after
  /// the completer has been completed (using [complete] or [completeError],
  /// which sets [isCompleted] to true) if completed with a [Future].
  /// The completer can be cancelled until the result becomes available,
  /// even if [isCompleted] is true.
  Future<void> _cancel() {
    if (_inner.isCompleted) return Future.value(null);

    if (!_isCanceled) {
      _isCanceled = true;
      var onCancel = _onCancel;
      _cancelCompleter
          .complete(onCancel == null ? null : Future.sync(onCancel));
    }
    return _cancelCompleter.future;
  }
}
