// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

/// A transformer that converts a broadcast stream into a single-subscription
/// stream.
///
/// This buffers the broadcast stream's events, which means that it starts
/// listening to a stream as soon as it's bound.
class SingleSubscriptionTransformer<S, T> implements StreamTransformer<S, T> {
  const SingleSubscriptionTransformer();

  Stream<T> bind(Stream<S> stream) {
    var subscription;
    var controller = new StreamController(sync: true,
        onCancel: () => subscription.cancel());
    subscription = stream.listen(controller.add,
        onError: controller.addError, onDone: controller.close);
    return controller.stream;
  }
}
