// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";

import "package:async/async.dart";
import "package:test/test.dart";

import "utils.dart";

main() {
  test("disallows a null callback", () {
    expect(() => new LazyStream(null), throwsArgumentError);
  });

  test("calls the callback when the stream is listened", () async {
    var callbackCalled = false;
    var stream = new LazyStream(expectAsync(() {
      callbackCalled = true;
      return new Stream.empty();
    }));

    await flushMicrotasks();
    expect(callbackCalled, isFalse);

    stream.listen(null);
    expect(callbackCalled, isTrue);
  });

  test("calls the callback when the stream is listened", () async {
    var callbackCalled = false;
    var stream = new LazyStream(expectAsync(() {
      callbackCalled = true;
      return new Stream.empty();
    }));

    await flushMicrotasks();
    expect(callbackCalled, isFalse);

    stream.listen(null);
    expect(callbackCalled, isTrue);
  });

  test("forwards to a synchronously-provided stream", () async {
    var controller = new StreamController<int>();
    var stream = new LazyStream(expectAsync(() => controller.stream));

    var events = [];
    stream.listen(events.add);

    controller.add(1);
    await flushMicrotasks();
    expect(events, equals([1]));

    controller.add(2);
    await flushMicrotasks();
    expect(events, equals([1, 2]));

    controller.add(3);
    await flushMicrotasks();
    expect(events, equals([1, 2, 3]));

    controller.close();
  });

  test("forwards to an asynchronously-provided stream", () async {
    var controller = new StreamController<int>();
    var stream = new LazyStream(expectAsync(() async => controller.stream));

    var events = [];
    stream.listen(events.add);

    controller.add(1);
    await flushMicrotasks();
    expect(events, equals([1]));

    controller.add(2);
    await flushMicrotasks();
    expect(events, equals([1, 2]));

    controller.add(3);
    await flushMicrotasks();
    expect(events, equals([1, 2, 3]));

    controller.close();
  });

  test("a lazy stream can't be listened to multiple times", () {
    var stream = new LazyStream(expectAsync(() => new Stream.empty()));
    expect(stream.isBroadcast, isFalse);

    stream.listen(null);
    expect(() => stream.listen(null), throwsStateError);
    expect(() => stream.listen(null), throwsStateError);
  });

  test("a lazy stream can't be listened to from within its callback", () {
    var stream;
    stream = new LazyStream(expectAsync(() {
      expect(() => stream.listen(null), throwsStateError);
      return new Stream.empty();
    }));
    stream.listen(null);
  });
}
