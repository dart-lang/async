// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import '../result.dart';
import 'capture_sink.dart';

/// Use [Result.captureTransformer] instead.
@Deprecated("Will be removed in async 2.0.0.")
class CaptureStreamTransformer<T> implements StreamTransformer<T, Result<T>> {
  const CaptureStreamTransformer();

  Stream<Result<T>> bind(Stream<T> source) {
    return new Stream<Result<T>>.eventTransformed(source, _createSink);
  }

  static EventSink _createSink(EventSink<Result> sink) {
    return new CaptureSink(sink);
  }
}
