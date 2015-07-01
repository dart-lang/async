// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:async";

import "package:async/async.dart" show SubscriptionStream;
import "package:test/test.dart";

import "utils.dart";

main() {
  test("subscription stream of an entire subscription", () async {
    var stream = createStream();
    var subscription = stream.listen(null);
    var subscriptionStream = new SubscriptionStream<int>(subscription);
    await flushMicrotasks();
    expect(subscriptionStream.toList(), completion([1, 2, 3, 4]));
  });

  test("subscription stream after two events", () async {
    var stream = createStream();
    var skips = 0;
    var completer = new Completer();
    var subscription;
    subscription = stream.listen((value) {
      ++skips;
      expect(value, skips);
      if (skips == 2) {
        completer.complete(new SubscriptionStream<int>(subscription));
      }
    });
    var subscriptionStream = await completer.future;
    await flushMicrotasks();
    expect(subscriptionStream.toList(), completion([3, 4]));
  });

  test("listening twice fails", () async {
    var stream = createStream();
    var sourceSubscription = stream.listen(null);
    var subscriptionStream = new SubscriptionStream<int>(sourceSubscription);
    var subscription = subscriptionStream.listen(null);
    expect(() => subscriptionStream.listen(null), throws);
    await subscription.cancel();
  });

  test("pause and cancel passed through to original stream", () async {
    var controller = new StreamController(onCancel: () async => 42);
    var sourceSubscription = controller.stream.listen(null);
    var subscriptionStream = new SubscriptionStream(sourceSubscription);
    expect(controller.isPaused, isTrue);
    var lastEvent;
    var subscription = subscriptionStream.listen((value) {
      lastEvent = value;
    });
    controller.add(1);

    await flushMicrotasks();
    expect(lastEvent, 1);
    expect(controller.isPaused, isFalse);

    subscription.pause();
    expect(controller.isPaused, isTrue);

    subscription.resume();
    expect(controller.isPaused, isFalse);

    expect(await subscription.cancel(), 42);
    expect(controller.hasListener, isFalse);
  });

  group("cancelOnError source:", () {
    for (var sourceCancels in [false, true]) {
      group("${sourceCancels ? "yes" : "no"}:", () {
        var subscriptionStream;
        setUp(() {
          var source = createErrorStream();
          var sourceSubscription = source.listen(null,
                                                 cancelOnError: sourceCancels);
          subscriptionStream = new SubscriptionStream<int>(sourceSubscription);
        });

        test("- subscriptionStream: no", () async {
          var done = new Completer();
          var events = [];
          var subscription = subscriptionStream.listen(events.add,
                                                       onError: events.add,
                                                       onDone: done.complete,
                                                       cancelOnError: false);
          var expected = [1, 2, "To err is divine!"];
          if (sourceCancels) {
            var timeout = done.future.timeout(const Duration(milliseconds: 5),
                                              onTimeout: () => true);
            expect(await timeout, true);
          } else {
            expected.add(4);
            await done.future;
          }
          expect(events, expected);
        });

        test("- subscriptionStream: yes", () async {
          var completer = new Completer();
          var events = [];
          subscriptionStream.listen(events.add,
                                    onError: (value) {
                                      events.add(value);
                                      completer.complete();
                                    },
                                    onDone: () => throw "should not happen",
                                    cancelOnError: true);
          await completer.future;
          await flushMicrotasks();
          expect(events, [1, 2, "To err is divine!"]);
        });
      });
    }

    for (var cancelOnError in [false, true]) {
      group(cancelOnError ? "yes" : "no", () {
        test("- no error, value goes to asFuture", () async {
          var stream = createStream();
          var sourceSubscription =
              stream.listen(null, cancelOnError: cancelOnError);
          var subscriptionStream =
              new SubscriptionStream(sourceSubscription);
          var subscription =
              subscriptionStream.listen(null, cancelOnError: cancelOnError);
          expect(subscription.asFuture(42), completion(42));
        });

        test("- error goes to asFuture", () async {
          var stream = createErrorStream();
          var sourceSubscription = stream.listen(null,
                                                 cancelOnError: cancelOnError);
          var subscriptionStream =
              new SubscriptionStream(sourceSubscription);

          var subscription =
              subscriptionStream.listen(null, cancelOnError: cancelOnError);
          expect(subscription.asFuture(), throws);
        });
      });
    }
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

Stream<int> createLongStream() async* {
  for (int i = 0; i < 200; i++) yield i;
}
