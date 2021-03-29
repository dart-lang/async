// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:async/chunked_stream.dart';

void main() {
  test('readChunkedStream', () async {
    final s = (() async* {
      yield ['a'];
      yield ['b'];
      yield ['c'];
    })();
    expect(await readChunkedStream(s), equals(['a', 'b', 'c']));
  });

  test('readByteStream', () async {
    final s = (() async* {
      yield [1, 2];
      yield Uint8List.fromList([3]);
      yield [4];
    })();
    final result = await readByteStream(s);
    expect(result, equals([1, 2, 3, 4]));
    expect(result, isA<Uint8List>());
  });
}
