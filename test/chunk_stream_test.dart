// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import 'package:chunked_stream/chunked_stream.dart';

void main() {
  for (var N = 1; N < 6; N++) {
    test('asChunkedStream (N = $N) preserves elements', () async {
      final s = (() async* {
        for (var j = 0; j < 97; j++) {
          yield j;
        }
      })();

      final result = await readChunkedStream(asChunkedStream(N, s));
      expect(result, hasLength(97));
      expect(result, equals(List.generate(97, (j) => j)));
    });

    test('asChunkedStream (N = $N) has chunk size N', () async {
      final s = (() async* {
        for (var j = 0; j < 97; j++) {
          yield j;
        }
      })();

      final chunks = await asChunkedStream(N, s).toList();

      // Last chunk may be smaller than N
      expect(chunks.removeLast(), hasLength(lessThanOrEqualTo(N)));
      // Last chunk must be N
      expect(chunks, everyElement(hasLength(N)));
    });
  }
}
