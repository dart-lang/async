// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE filevents.

import "dart:async";

import "package:async/async.dart" show StreamQueue;
import "package:test/test.dart";

import "utils.dart";

main() {
  group("source stream", () {
    test("is listened to on first request, paused between requests", () async {
      var controller = new StreamController();
      var events = new StreamQueue<int>(controller.stream);
      await flushMicrotasks();
      expect(controller.hasListener, isFalse);

      var next = events.next;
      expect(controller.hasListener, isTrue);
      expect(controller.isPaused, isFalse);

      controller.add(1);

      expect(await next, 1);
      expect(controller.hasListener, isTrue);
      expect(controller.isPaused, isTrue);

      next = events.next;
      expect(controller.hasListener, isTrue);
      expect(controller.isPaused, isFalse);

      controller.add(2);

      expect(await next, 2);
      expect(controller.hasListener, isTrue);
      expect(controller.isPaused, isTrue);

      events.cancel();
      expect(controller.hasListener, isFalse);
    });
  });

  group("next operation", () {
    test("simple sequence of requests", () async {
      var events = new StreamQueue<int>(createStream());
      for (int i = 1; i <= 4; i++) {
        expect(await events.next, i);
      }
      expect(events.next, throwsStateError);
    });

    test("multiple requests at the same time", () async {
      var events = new StreamQueue<int>(createStream());
      var result = await Future.wait(
          [events.next, events.next, events.next, events.next]);
      expect(result, [1, 2, 3, 4]);
      await events.cancel();
    });

    test("sequence of requests with error", () async {
      var events = new StreamQueue<int>(createErrorStream());
      expect(await events.next, 1);
      expect(await events.next, 2);
      expect(events.next, throwsA("To err is divine!"));
      expect(await events.next, 4);
      await events.cancel();
    });
  });

  group("skip operation", () {
    test("of two elements in the middle of sequence", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.next, 1);
      expect(await events.skip(2), 0);
      expect(await events.next, 4);
      await events.cancel();
    });

    test("with negative/bad arguments throws", () async {
      var events = new StreamQueue<int>(createStream());
      expect(() => events.skip(-1), throwsArgumentError);
      // A non-int throws either a type error or an argument error,
      // depending on whether it's checked mode or not.
      expect(await events.next, 1);  // Did not consume event.
      expect(() => events.skip(-1), throwsArgumentError);
      expect(await events.next, 2);  // Did not consume event.
      await events.cancel();
    });

    test("of 0 elements works", () async {
      var events = new StreamQueue<int>(createStream());
      expect(events.skip(0), completion(0));
      expect(events.next, completion(1));
      expect(events.skip(0), completion(0));
      expect(events.next, completion(2));
      expect(events.skip(0), completion(0));
      expect(events.next, completion(3));
      expect(events.skip(0), completion(0));
      expect(events.next, completion(4));
      expect(events.skip(0), completion(0));
      expect(events.skip(5), completion(5));
      expect(events.next, throwsStateError);
      await events.cancel();
    });

    test("of too many events ends at stream start", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.skip(6), 2);
      await events.cancel();
    });

    test("of too many events after some events", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.next, 1);
      expect(await events.next, 2);
      expect(await events.skip(6), 4);
      await events.cancel();
    });

    test("of too many events ends at stream end", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.next, 1);
      expect(await events.next, 2);
      expect(await events.next, 3);
      expect(await events.next, 4);
      expect(await events.skip(2), 2);
      await events.cancel();
    });

    test("of events with error", () async {
      var events = new StreamQueue<int>(createErrorStream());
      expect(events.skip(4), throwsA("To err is divine!"));
      expect(await events.next, 4);
      await events.cancel();
    });

    test("of events with error, and skip again after", () async {
      var events = new StreamQueue<int>(createErrorStream());
      expect(events.skip(4), throwsA("To err is divine!"));
      expect(events.skip(2), completion(1));
      await events.cancel();
    });
    test("multiple skips at same time complete in order.", () async {
      var events = new StreamQueue<int>(createStream());
      var skip1 = events.skip(1);
      var skip2 = events.skip(0);
      var skip3 = events.skip(4);
      var skip4 = events.skip(1);
      var index = 0;
      // Check that futures complete in order.
      sequence(expectedValue, sequenceIndex) => (value) {
        expect(value, expectedValue);
        expect(index, sequenceIndex);
        index++;
      };
      await Future.wait([skip1.then(sequence(0, 0)),
                         skip2.then(sequence(0, 1)),
                         skip3.then(sequence(1, 2)),
                         skip4.then(sequence(1, 3))]);
      await events.cancel();
    });
  });

  group("take operation", () {
    test("as simple take of events", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.next, 1);
      expect(await events.take(2), [2, 3]);
      expect(await events.next, 4);
      await events.cancel();
    });

    test("of 0 events", () async {
      var events = new StreamQueue<int>(createStream());
      expect(events.take(0), completion([]));
      expect(events.next, completion(1));
      expect(events.take(0), completion([]));
      expect(events.next, completion(2));
      expect(events.take(0), completion([]));
      expect(events.next, completion(3));
      expect(events.take(0), completion([]));
      expect(events.next, completion(4));
      expect(events.take(0), completion([]));
      expect(events.take(5), completion([]));
      expect(events.next, throwsStateError);
      await events.cancel();
    });

    test("with bad arguments throws", () async {
      var events = new StreamQueue<int>(createStream());
      expect(() => events.take(-1), throwsArgumentError);
      expect(await events.next, 1);  // Did not consume event.
      expect(() => events.take(-1), throwsArgumentError);
      expect(await events.next, 2);  // Did not consume event.
      await events.cancel();
    });

    test("of too many arguments", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.take(6), [1, 2, 3, 4]);
      await events.cancel();
    });

    test("too large later", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.next, 1);
      expect(await events.next, 2);
      expect(await events.take(6), [3, 4]);
      await events.cancel();
    });

    test("error", () async {
      var events = new StreamQueue<int>(createErrorStream());
      expect(events.take(4), throwsA("To err is divine!"));
      expect(await events.next, 4);
      await events.cancel();
    });
  });

  group("rest operation", () {
    test("after single next", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.next, 1);
      expect(await events.rest.toList(), [2, 3, 4]);
    });

    test("at start", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.rest.toList(), [1, 2, 3, 4]);
    });

    test("at end", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.next, 1);
      expect(await events.next, 2);
      expect(await events.next, 3);
      expect(await events.next, 4);
      expect(await events.rest.toList(), isEmpty);
    });

    test("after end", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.next, 1);
      expect(await events.next, 2);
      expect(await events.next, 3);
      expect(await events.next, 4);
      expect(events.next, throwsStateError);
      expect(await events.rest.toList(), isEmpty);
    });

    test("after receiving done requested before", () async {
      var events = new StreamQueue<int>(createStream());
      var next1 = events.next;
      var next2 = events.next;
      var next3 = events.next;
      var rest = events.rest;
      for (int i = 0; i < 10; i++) {
        await flushMicrotasks();
      }
      expect(await next1, 1);
      expect(await next2, 2);
      expect(await next3, 3);
      expect(await rest.toList(), [4]);
    });

    test("with an error event error", () async {
      var events = new StreamQueue<int>(createErrorStream());
      expect(await events.next, 1);
      var rest = events.rest;
      var events2 = new StreamQueue(rest);
      expect(await events2.next, 2);
      expect(events2.next, throwsA("To err is divine!"));
      expect(await events2.next, 4);
    });

    test("closes the events, prevents other operations", () async {
      var events = new StreamQueue<int>(createStream());
      var stream = events.rest;
      expect(() => events.next, throwsStateError);
      expect(() => events.skip(1), throwsStateError);
      expect(() => events.take(1), throwsStateError);
      expect(() => events.rest, throwsStateError);
      expect(() => events.cancel(), throwsStateError);
      expect(stream.toList(), completion([1, 2, 3, 4]));
    });

    test("forwards to underlying stream", () async {
      var cancel = new Completer();
      var controller = new StreamController(onCancel: () => cancel.future);
      var events = new StreamQueue<int>(controller.stream);
      expect(controller.hasListener, isFalse);
      var next = events.next;
      expect(controller.hasListener, isTrue);
      expect(controller.isPaused, isFalse);

      controller.add(1);
      expect(await next, 1);
      expect(controller.isPaused, isTrue);

      var rest = events.rest;
      var subscription = rest.listen(null);
      expect(controller.hasListener, isTrue);
      expect(controller.isPaused, isFalse);

      var lastEvent;
      subscription.onData((value) => lastEvent = value);

      controller.add(2);

      await flushMicrotasks();
      expect(lastEvent, 2);
      expect(controller.hasListener, isTrue);
      expect(controller.isPaused, isFalse);

      subscription.pause();
      expect(controller.isPaused, isTrue);

      controller.add(3);

      await flushMicrotasks();
      expect(lastEvent, 2);
      subscription.resume();

      await flushMicrotasks();
      expect(lastEvent, 3);

      var cancelFuture = subscription.cancel();
      expect(controller.hasListener, isFalse);
      cancel.complete(42);
      expect(cancelFuture, completion(42));
    });
  });

  group("close operation", () {
    test("closes the events, prevents any other operation", () async {
      var events = new StreamQueue<int>(createStream());
      await events.cancel();
      expect(() => events.next, throwsStateError);
      expect(() => events.skip(1), throwsStateError);
      expect(() => events.take(1), throwsStateError);
      expect(() => events.rest, throwsStateError);
      expect(() => events.cancel(), throwsStateError);
    });

    test("cancels underlying subscription, returns result", () async {
      var cancelFuture = new Future.value(42);
      var controller = new StreamController(onCancel: () => cancelFuture);
      var events = new StreamQueue<int>(controller.stream);
      controller.add(1);
      expect(await events.next, 1);
      expect(await events.cancel(), 42);
    });
  });


  group("hasNext operation", () {
    test("true at start", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.hasNext, isTrue);
    });

    test("true after start", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.next, 1);
      expect(await events.hasNext, isTrue);
    });

    test("true at end", () async {
      var events = new StreamQueue<int>(createStream());
      for (int i = 1; i <= 4; i++) {
        expect(await events.next, i);
      }
      expect(await events.hasNext, isFalse);
    });

    test("true when enqueued", () async {
      var events = new StreamQueue<int>(createStream());
      var values = [];
      for (int i = 1; i <= 3; i++) {
        events.next.then(values.add);
      }
      expect(values, isEmpty);
      expect(await events.hasNext, isTrue);
      expect(values, [1, 2, 3]);
    });

    test("false when enqueued", () async {
      var events = new StreamQueue<int>(createStream());
      var values = [];
      for (int i = 1; i <= 4; i++) {
        events.next.then(values.add);
      }
      expect(values, isEmpty);
      expect(await events.hasNext, isFalse);
      expect(values, [1, 2, 3, 4]);
    });

    test("true when data event", () async {
      var controller = new StreamController();
      var events = new StreamQueue<int>(controller.stream);

      var hasNext;
      events.hasNext.then((result) { hasNext = result; });
      await flushMicrotasks();
      expect(hasNext, isNull);
      controller.add(42);
      expect(hasNext, isNull);
      await flushMicrotasks();
      expect(hasNext, isTrue);
    });

    test("true when error event", () async {
      var controller = new StreamController();
      var events = new StreamQueue<int>(controller.stream);

      var hasNext;
      events.hasNext.then((result) { hasNext = result; });
      await flushMicrotasks();
      expect(hasNext, isNull);
      controller.addError("BAD");
      expect(hasNext, isNull);
      await flushMicrotasks();
      expect(hasNext, isTrue);
      expect(events.next, throwsA("BAD"));
    });

    test("- hasNext after hasNext", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.hasNext, true);
      expect(await events.hasNext, true);
      expect(await events.next, 1);
      expect(await events.hasNext, true);
      expect(await events.hasNext, true);
      expect(await events.next, 2);
      expect(await events.hasNext, true);
      expect(await events.hasNext, true);
      expect(await events.next, 3);
      expect(await events.hasNext, true);
      expect(await events.hasNext, true);
      expect(await events.next, 4);
      expect(await events.hasNext, false);
      expect(await events.hasNext, false);
    });

    test("- next after true", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.next, 1);
      expect(await events.hasNext, true);
      expect(await events.next, 2);
      expect(await events.next, 3);
    });

    test("- next after true, enqueued", () async {
      var events = new StreamQueue<int>(createStream());
      var responses = [];
      events.next.then(responses.add);
      events.hasNext.then(responses.add);
      events.next.then(responses.add);
      do {
        await flushMicrotasks();
      } while (responses.length < 3);
      expect(responses, [1, true, 2]);
    });

    test("- skip 0 after true", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.next, 1);
      expect(await events.hasNext, true);
      expect(await events.skip(0), 0);
      expect(await events.next, 2);
    });

    test("- skip 1 after true", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.next, 1);
      expect(await events.hasNext, true);
      expect(await events.skip(1), 0);
      expect(await events.next, 3);
    });

    test("- skip 2 after true", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.next, 1);
      expect(await events.hasNext, true);
      expect(await events.skip(2), 0);
      expect(await events.next, 4);
    });

    test("- take 0 after true", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.next, 1);
      expect(await events.hasNext, true);
      expect(await events.take(0), isEmpty);
      expect(await events.next, 2);
    });

    test("- take 1 after true", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.next, 1);
      expect(await events.hasNext, true);
      expect(await events.take(1), [2]);
      expect(await events.next, 3);
    });

    test("- take 2 after true", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.next, 1);
      expect(await events.hasNext, true);
      expect(await events.take(2), [2, 3]);
      expect(await events.next, 4);
    });

    test("- rest after true", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.next, 1);
      expect(await events.hasNext, true);
      var stream = events.rest;
      expect(await stream.toList(), [2, 3, 4]);
    });

    test("- rest after true, at last", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.next, 1);
      expect(await events.next, 2);
      expect(await events.next, 3);
      expect(await events.hasNext, true);
      var stream = events.rest;
      expect(await stream.toList(), [4]);
    });

    test("- rest after false", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.next, 1);
      expect(await events.next, 2);
      expect(await events.next, 3);
      expect(await events.next, 4);
      expect(await events.hasNext, false);
      var stream = events.rest;
      expect(await stream.toList(), isEmpty);
    });

    test("- cancel after true on data", () async {
      var events = new StreamQueue<int>(createStream());
      expect(await events.next, 1);
      expect(await events.next, 2);
      expect(await events.hasNext, true);
      expect(await events.cancel(), null);
    });

    test("- cancel after true on error", () async {
      var events = new StreamQueue<int>(createErrorStream());
      expect(await events.next, 1);
      expect(await events.next, 2);
      expect(await events.hasNext, true);
      expect(await events.cancel(), null);
    });
  });

  test("all combinations sequential skip/next/take operations", () async {
    // Takes all combinations of two of next, skip and take, then ends with
    // doing rest. Each of the first rounds do 10 events of each type,
    // the rest does 20 elements.
    var eventCount = 20 * (3 * 3 + 1);
    var events = new StreamQueue<int>(createLongStream(eventCount));

    // Test expecting [startIndex .. startIndex + 9] as events using
    // `next`.
    nextTest(startIndex) {
      for (int i = 0; i < 10; i++) {
        expect(events.next, completion(startIndex + i));
      }
    }

    // Test expecting 10 events to be skipped.
    skipTest(startIndex) {
      expect(events.skip(10), completion(0));
    }

    // Test expecting [startIndex .. startIndex + 9] as events using
    // `take(10)`.
    takeTest(startIndex) {
      expect(events.take(10),
             completion(new List.generate(10, (i) => startIndex + i)));
    }
    var tests = [nextTest, skipTest, takeTest];

    int counter = 0;
    // Run through all pairs of two tests and run them.
    for (int i = 0; i < tests.length; i++) {
      for (int j = 0; j < tests.length; j++) {
        tests[i](counter);
        tests[j](counter + 10);
        counter += 20;
      }
    }
    // Then expect 20 more events as a `rest` call.
    expect(events.rest.toList(),
           completion(new List.generate(20, (i) => counter + i)));
  });
}

Stream<int> createStream() async* {
  yield 1;
  await flushMicrotasks();
  yield 2;
  await flushMicrotasks();
  yield 3;
  await flushMicrotasks();
  yield 4;
}

Stream<int> createErrorStream() {
  StreamController controller = new StreamController<int>();
  () async {
    controller.add(1);
    await flushMicrotasks();
    controller.add(2);
    await flushMicrotasks();
    controller.addError("To err is divine!");
    await flushMicrotasks();
    controller.add(4);
    await flushMicrotasks();
    controller.close();
  }();
  return controller.stream;
}

Stream<int> createLongStream(int eventCount) async* {
  for (int i = 0; i < eventCount; i++) yield i;
}
