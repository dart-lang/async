// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'async_memoizer.dart';
import 'delegate/stream_subscription.dart';

typedef Future _AsyncHandler<T>(StreamSubscription<T> inner);

typedef void _VoidHandler<T>(StreamSubscription<T> inner);

/// Creates a [StreamTransformer] that modifies the behavior of subscriptions to
/// a stream.
///
/// When [StreamSubscription.cancel], [StreamSubscription.pause], or
/// [StreamSubscription.resume] is called, the corresponding handler is invoked.
/// By default, handlers just forward to the underlying subscription.
///
/// Guarantees that once the transformed [StreamSubscription] has been canceled,
/// no further callbacks will be invoked. The [handlePause] and [handleResume]
/// are invoked regardless of whether the subscription is paused already or not.
///
/// In order to preserve [StreamSubscription] guarantees, **all callbacks must
/// synchronously call the corresponding method** on the inner
/// [StreamSubscription]: [handleCancel] must call `cancel()`, [handlePause]
/// must call `pause()`, and [handleResume] must call `resume()`.
StreamTransformer/*<T, T>*/ subscriptionTransformer/*<T>*/(
    {Future handleCancel(StreamSubscription/*<T>*/ inner),
    void handlePause(StreamSubscription/*<T>*/ inner),
    void handleResume(StreamSubscription/*<T>*/ inner)}) {
  return new StreamTransformer((stream, cancelOnError) {
    return new _TransformedSubscription(
        stream.listen(null, cancelOnError: cancelOnError),
        handleCancel ?? (inner) => inner.cancel(),
        handlePause ?? (inner) {
          inner.pause();
        },
        handleResume ?? (inner) {
          inner.resume();
        });
  });
}

/// A [StreamSubscription] wrapper that calls callbacks for subscription
/// methods.
class _TransformedSubscription<T> extends DelegatingStreamSubscription<T> {
  /// The wrapped subscription.
  final StreamSubscription<T> _inner;

  /// The callback to run when [cancel] is called.
  final _AsyncHandler<T> _handleCancel;

  /// The callback to run when [pause] is called.
  final _VoidHandler<T> _handlePause;

  /// The callback to run when [resume] is called.
  final _VoidHandler<T> _handleResume;

  _TransformedSubscription(StreamSubscription<T> inner,
          this._handleCancel, this._handlePause, this._handleResume)
      : _inner = inner,
        super(inner);

  Future cancel() => _cancelMemoizer.runOnce(() => _handleCancel(_inner));
  final _cancelMemoizer = new AsyncMemoizer();

  void pause([Future resumeFuture]) {
    if (_cancelMemoizer.hasRun) return;
    if (resumeFuture != null) resumeFuture.whenComplete(resume);
    _handlePause(_inner);
  }

  void resume() {
    if (_cancelMemoizer.hasRun) return;
    _handleResume(_inner);
  }
}
