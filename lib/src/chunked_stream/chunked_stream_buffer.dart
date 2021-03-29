// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

/// Buffer an chunked stream.
///
/// This reads [input] into an internal buffer of size [bufferSize] elements.
/// When the internal buffer is full the [input] stream is _paused_, as elements
/// are consumed from the stream returned the [input] stream in _resumed_.
///
/// If reading from a chunked stream as it arrives from disk or network it can
/// be useful to buffer the stream internally to avoid blocking disk or network
/// reads while waiting for CPU to process the bytes read.
Stream<List<T>> bufferChunkedStream<T>(
  Stream<List<T>> input, {
  int bufferSize = 16 * 1024,
}) async* {
  if (bufferSize <= 0) {
    throw ArgumentError.value(
        bufferSize, 'bufferSize', 'bufferSize must be positive');
  }

  late final StreamController<List<T>> c;
  StreamSubscription? sub;

  c = StreamController(
    onListen: () {
      sub = input.listen((chunk) {
        bufferSize -= chunk.length;
        c.add(chunk);

        final currentSub = sub;
        if (bufferSize <= 0 && currentSub != null && !currentSub.isPaused) {
          currentSub.pause();
        }
      }, onDone: () {
        c.close();
      }, onError: (e, st) {
        c.addError(e, st);
      });
    },
    onCancel: () => sub!.cancel(),
  );

  await for (final chunk in c.stream) {
    yield chunk;
    bufferSize += chunk.length;

    final currentSub = sub;
    if (bufferSize > 0 && currentSub != null && currentSub.isPaused) {
      currentSub.resume();
    }
  }
}
