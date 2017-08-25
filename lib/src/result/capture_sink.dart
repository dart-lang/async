// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'result.dart';

/// Used by [Result.captureSink].
class CaptureSink<T> implements EventSink<T> {
  final EventSink<Result<T>> _sink;

  CaptureSink(EventSink<Result<T>> sink) : _sink = sink;

  void add(T value) {
    _sink.add(new Result.value(value));
  }

  void addError(Object error, [StackTrace stackTrace]) {
    _sink.add(new Result.error(error, stackTrace));
  }

  void close() {
    _sink.close();
  }
}
