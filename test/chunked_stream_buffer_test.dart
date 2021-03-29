// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import 'package:async/chunked_stream.dart';

void main() {
  for (var i = 1; i < 6; i++) {
    test('bufferChunkedStream (bufferSize: $i)', () async {
      final s = (() async* {
        yield ['a'];
        yield ['b'];
        yield ['c'];
      })();

      final bs = bufferChunkedStream(s, bufferSize: i);
      final result = await readChunkedStream(bs);
      expect(result, equals(['a', 'b', 'c']));
    });
  }
}
