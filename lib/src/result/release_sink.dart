// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'result.dart';

/// Used by [Result.releaseSink].
class ReleaseSink<T> implements EventSink<Result<T>> {
  final EventSink _sink;

  ReleaseSink(EventSink<T> sink) : _sink = sink;

  void add(Result<T> result) {
    result.addTo(_sink);
  }

  void addError(Object error, [StackTrace stackTrace]) {
    // Errors may be added by intermediate processing, even if it is never
    // added by CaptureSink.
    _sink.addError(error, stackTrace);
  }

  void close() {
    _sink.close();
  }
}
