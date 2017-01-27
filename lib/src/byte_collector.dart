// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import "dart:typed_data";

/// Collects an asynchronous sequence of byte lists into a single list of bytes.
///
/// If the [source] stream emits an error event,
/// the collection fails and the returned future completes with the same error.
///
/// If any of the input data are not valid bytes, they will be truncated to
/// an eight-bit unsigned value in the resulting list.
Future<Uint8List> collectBytes(Stream<List<int>> source) {
  var byteLists = List<List<int>>[];
  var length = 0;
  var completer = new Completer<Uint8List>.sync();
  source.listen(
      (bytes) {
        byteLists.add(bytes);
        length += bytes.length;
      },
      onError: completer.completeError,
      onDone: () {
        completer.complete(_collect(length, byteLists));
      },
      cancelOnError: true);
  return completer.future;
}

// Join a lists of bytes with a known total length into a single [Uint8List].
Uint8List _collect(int length, List<List<int>> byteLists) {
  var result = new Uint8List(length);
  int i = 0;
  for (var byteList in byteLists) {
    var end = i + byteList.length;
    result.setRange(i, end, byteList);
    i = end;
  }
  return result;
}
