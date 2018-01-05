// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'result.dart';
import 'release_sink.dart';

/// A transformer that releases result events as data and error events.
class ReleaseStreamTransformer<T> implements StreamTransformer<Result<T>, T> {
  const ReleaseStreamTransformer();

  Stream<T> bind(Stream<Result<T>> source) {
    return new Stream<T>.eventTransformed(source, _createSink);
  }

  // Since Stream.eventTransformed is not generic, this method can be static.
  static EventSink<Result> _createSink(EventSink sink) => new ReleaseSink(sink);
}
