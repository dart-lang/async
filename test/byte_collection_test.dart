// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";
import "dart:typed_data";

import "package:test/test.dart";
import "package:async/async.dart" show byteCollector, collectBytes, Result;

void main() {
  group("collectBytes", () {
    test("simple list and overflow", () {
      var result = collectBytes(new Stream.fromIterable([
        [0],
        [1],
        [2],
        [256]
      ]));
      expect(result, completion([0, 1, 2, 0]));
    });

    test("no events", () {
      var result = collectBytes(new Stream.fromIterable([]));
      expect(result, completion([]));
    });

    test("empty events", () {
      var result = collectBytes(new Stream.fromIterable([[], []]));
      expect(result, completion([]));
    });

    test("error event", () {
      var result = collectBytes(new Stream.fromIterable(
          new Iterable.generate(3, (n) => n == 2 ? throw "badness" : [n])));
      expect(result, throwsA("badness"));
    });
  });
}
