// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:test/test.dart';

void main() {
  group('single-subscription', () {
    StreamGroup<String> streamGroup;
    setUp(() {
      streamGroup = StreamGroup<String>();
    });

    test('buffers events from multiple sources', () async {
      var controller1 = StreamController<String>();
      streamGroup.add(controller1.stream);
      controller1.add('first');
      controller1.close();

      var controller2 = StreamController<String>();
      streamGroup.add(controller2.stream);
      controller2.add('second');
      controller2.close();

      await flushMicrotasks();

      expect(streamGroup.close(), completes);

      expect(streamGroup.stream.toList(),
          completion(unorderedEquals(['first', 'second'])));
    });

    test('buffers errors from multiple sources', () async {
      var controller1 = StreamController<String>();
      streamGroup.add(controller1.stream);
      controller1.addError('first');
      controller1.close();

      var controller2 = StreamController<String>();
      streamGroup.add(controller2.stream);
      controller2.addError('second');
      controller2.close();

      await flushMicrotasks();

      expect(streamGroup.close(), completes);

      var transformed = streamGroup.stream.transform(
          StreamTransformer<String, String>.fromHandlers(
              handleError: (error, _, sink) => sink.add('error: $error')));
      expect(transformed.toList(),
          completion(equals(['error: first', 'error: second'])));
    });

    test('buffers events and errors together', () async {
      var controller = StreamController<String>();
      streamGroup.add(controller.stream);

      controller.add('first');
      controller.addError('second');
      controller.add('third');
      controller.addError('fourth');
      controller.addError('fifth');
      controller.add('sixth');
      controller.close();

      await flushMicrotasks();

      expect(streamGroup.close(), completes);

      var transformed = streamGroup.stream.transform(
          StreamTransformer<String, String>.fromHandlers(
              handleData: (data, sink) => sink.add('data: $data'),
              handleError: (error, _, sink) => sink.add('error: $error')));
      expect(
          transformed.toList(),
          completion(equals([
            'data: first',
            'error: second',
            'data: third',
            'error: fourth',
            'error: fifth',
            'data: sixth'
          ])));
    });

    test("emits events once there's a listener", () {
      var controller = StreamController<String>();
      streamGroup.add(controller.stream);

      expect(
          streamGroup.stream.toList(), completion(equals(['first', 'second'])));

      controller.add('first');
      controller.add('second');
      controller.close();

      expect(streamGroup.close(), completes);
    });

    test("doesn't buffer events from a broadcast stream", () async {
      var controller = StreamController<String>.broadcast();
      streamGroup.add(controller.stream);

      controller.add('first');
      controller.add('second');
      controller.close();

      await flushMicrotasks();

      expect(streamGroup.close(), completes);
      expect(streamGroup.stream.toList(), completion(isEmpty));
    });

    test('when paused, buffers events from a broadcast stream', () async {
      var controller = StreamController<String>.broadcast();
      streamGroup.add(controller.stream);

      var events = [];
      var subscription = streamGroup.stream.listen(events.add);
      subscription.pause();

      controller.add('first');
      controller.add('second');
      controller.close();
      await flushMicrotasks();

      subscription.resume();
      expect(streamGroup.close(), completes);
      await flushMicrotasks();

      expect(events, equals(['first', 'second']));
    });

    test("emits events from a broadcast stream once there's a listener", () {
      var controller = StreamController<String>.broadcast();
      streamGroup.add(controller.stream);

      expect(
          streamGroup.stream.toList(), completion(equals(['first', 'second'])));

      controller.add('first');
      controller.add('second');
      controller.close();

      expect(streamGroup.close(), completes);
    });

    test('forwards cancel errors', () async {
      var subscription = streamGroup.stream.listen(null);

      var controller = StreamController<String>(onCancel: () => throw 'error');
      streamGroup.add(controller.stream);
      await flushMicrotasks();

      expect(subscription.cancel(), throwsA('error'));
    });

    test('forwards a cancel future', () async {
      var subscription = streamGroup.stream.listen(null);

      var completer = Completer();
      var controller =
          StreamController<String>(onCancel: () => completer.future);
      streamGroup.add(controller.stream);
      await flushMicrotasks();

      var fired = false;
      subscription.cancel().then((_) => fired = true);

      await flushMicrotasks();
      expect(fired, isFalse);

      completer.complete();
      await flushMicrotasks();
      expect(fired, isTrue);
    });

    test(
        'add() while active pauses the stream if the group is paused, then '
        'resumes once the group resumes', () async {
      var subscription = streamGroup.stream.listen(null);
      await flushMicrotasks();

      var paused = false;
      var controller = StreamController<String>(
          onPause: () => paused = true, onResume: () => paused = false);

      subscription.pause();
      await flushMicrotasks();

      streamGroup.add(controller.stream);
      await flushMicrotasks();
      expect(paused, isTrue);

      subscription.resume();
      await flushMicrotasks();
      expect(paused, isFalse);
    });

    group('add() while canceled', () {
      setUp(() async {
        streamGroup.stream.listen(null).cancel();
        await flushMicrotasks();
      });

      test('immediately listens to and cancels the stream', () async {
        var listened = false;
        var canceled = false;
        var controller = StreamController<String>(onListen: () {
          listened = true;
        }, onCancel: expectAsync0(() {
          expect(listened, isTrue);
          canceled = true;
        }));

        streamGroup.add(controller.stream);
        await flushMicrotasks();
        expect(listened, isTrue);
        expect(canceled, isTrue);
      });

      test('forwards cancel errors', () {
        var controller =
            StreamController<String>(onCancel: () => throw 'error');

        expect(streamGroup.add(controller.stream), throwsA('error'));
      });

      test('forwards a cancel future', () async {
        var completer = Completer();
        var controller =
            StreamController<String>(onCancel: () => completer.future);

        var fired = false;
        streamGroup.add(controller.stream).then((_) => fired = true);

        await flushMicrotasks();
        expect(fired, isFalse);

        completer.complete();
        await flushMicrotasks();
        expect(fired, isTrue);
      });
    });
  });

  group('broadcast', () {
    StreamGroup<String> streamGroup;
    setUp(() {
      streamGroup = StreamGroup<String>.broadcast();
    });

    test('buffers events from multiple sources', () async {
      var controller1 = StreamController<String>();
      streamGroup.add(controller1.stream);
      controller1.add('first');
      controller1.close();

      var controller2 = StreamController<String>();
      streamGroup.add(controller2.stream);
      controller2.add('second');
      controller2.close();

      await flushMicrotasks();

      expect(streamGroup.close(), completes);

      expect(
          streamGroup.stream.toList(), completion(equals(['first', 'second'])));
    });

    test("emits events from multiple sources once there's a listener", () {
      var controller1 = StreamController<String>();
      streamGroup.add(controller1.stream);

      var controller2 = StreamController<String>();
      streamGroup.add(controller2.stream);

      expect(
          streamGroup.stream.toList(), completion(equals(['first', 'second'])));

      controller1.add('first');
      controller2.add('second');
      controller1.close();
      controller2.close();

      expect(streamGroup.close(), completes);
    });

    test("doesn't buffer events once a listener has been added and removed",
        () async {
      var controller = StreamController<String>();
      streamGroup.add(controller.stream);

      streamGroup.stream.listen(null).cancel();
      await flushMicrotasks();

      controller.add('first');
      controller.addError('second');
      controller.close();

      await flushMicrotasks();

      expect(streamGroup.close(), completes);
      expect(streamGroup.stream.toList(), completion(isEmpty));
    });

    test("doesn't buffer events from a broadcast stream", () async {
      var controller = StreamController<String>.broadcast();
      streamGroup.add(controller.stream);
      controller.add('first');
      controller.addError('second');
      controller.close();

      await flushMicrotasks();

      expect(streamGroup.close(), completes);
      expect(streamGroup.stream.toList(), completion(isEmpty));
    });

    test("emits events from a broadcast stream once there's a listener", () {
      var controller = StreamController<String>.broadcast();
      streamGroup.add(controller.stream);

      expect(
          streamGroup.stream.toList(), completion(equals(['first', 'second'])));

      controller.add('first');
      controller.add('second');
      controller.close();

      expect(streamGroup.close(), completes);
    });

    test('cancels and re-listens broadcast streams', () async {
      var subscription = streamGroup.stream.listen(null);

      var controller = StreamController<String>.broadcast();

      streamGroup.add(controller.stream);
      await flushMicrotasks();
      expect(controller.hasListener, isTrue);

      subscription.cancel();
      await flushMicrotasks();
      expect(controller.hasListener, isFalse);

      streamGroup.stream.listen(null);
      await flushMicrotasks();
      expect(controller.hasListener, isTrue);
    });

    test('never cancels single-subscription streams', () async {
      var subscription = streamGroup.stream.listen(null);

      var controller =
          StreamController<String>(onCancel: expectAsync0(() {}, count: 0));

      streamGroup.add(controller.stream);
      await flushMicrotasks();

      subscription.cancel();
      await flushMicrotasks();

      streamGroup.stream.listen(null);
      await flushMicrotasks();
    });

    test('drops events from a single-subscription stream while dormant',
        () async {
      var events = [];
      var subscription = streamGroup.stream.listen(events.add);

      var controller = StreamController<String>();
      streamGroup.add(controller.stream);
      await flushMicrotasks();

      controller.add('first');
      await flushMicrotasks();
      expect(events, equals(['first']));

      subscription.cancel();
      controller.add('second');
      await flushMicrotasks();
      expect(events, equals(['first']));

      streamGroup.stream.listen(events.add);
      controller.add('third');
      await flushMicrotasks();
      expect(events, equals(['first', 'third']));
    });

    test('a single-subscription stream can be removed while dormant', () async {
      var controller = StreamController<String>();
      streamGroup.add(controller.stream);
      await flushMicrotasks();

      streamGroup.stream.listen(null).cancel();
      await flushMicrotasks();

      streamGroup.remove(controller.stream);
      expect(controller.hasListener, isFalse);
      await flushMicrotasks();

      expect(streamGroup.stream.toList(), completion(isEmpty));
      controller.add('first');
      expect(streamGroup.close(), completes);
    });
  });

  group('regardless of type', () {
    group('single-subscription', () {
      regardlessOfType(() => StreamGroup<String>());
    });

    group('broadcast', () {
      regardlessOfType(() => StreamGroup<String>.broadcast());
    });
  });

  test('merge() emits events from all components streams', () async {
    var controller1 = StreamController<String>();
    var controller2 = StreamController<String>();

    var merged = StreamGroup.merge([controller1.stream, controller2.stream]);

    controller1.add('first');
    controller1.close();
    controller2.add('second');
    controller2.close();

    expect(await merged.toList(), ['first', 'second']);
  });

  test('mergeBroadcast() emits events from all components streams', () async {
    var controller1 = StreamController<String>();
    var controller2 = StreamController<String>();

    var merged =
        StreamGroup.mergeBroadcast([controller1.stream, controller2.stream]);

    controller1.add('first');
    controller1.close();
    controller2.add('second');
    controller2.close();

    expect(merged.isBroadcast, isTrue);

    expect(await merged.toList(), ['first', 'second']);
  });
}

void regardlessOfType(StreamGroup<String> Function() newStreamGroup) {
  StreamGroup<String> streamGroup;
  setUp(() {
    streamGroup = newStreamGroup();
  });

  group('add()', () {
    group('while dormant', () {
      test("doesn't listen to the stream until the group is listened to",
          () async {
        var controller = StreamController<String>();

        expect(streamGroup.add(controller.stream), isNull);
        await flushMicrotasks();
        expect(controller.hasListener, isFalse);

        streamGroup.stream.listen(null);
        await flushMicrotasks();
        expect(controller.hasListener, isTrue);
      });

      test('is a no-op if the stream is already in the group', () {
        var controller = StreamController<String>();
        streamGroup.add(controller.stream);
        streamGroup.add(controller.stream);
        streamGroup.add(controller.stream);

        // If the stream was actually listened to multiple times, this would
        // throw a StateError.
        streamGroup.stream.listen(null);
      });
    });

    group('while active', () {
      setUp(() async {
        streamGroup.stream.listen(null);
        await flushMicrotasks();
      });

      test('listens to the stream immediately', () async {
        var controller = StreamController<String>();

        expect(streamGroup.add(controller.stream), isNull);
        await flushMicrotasks();
        expect(controller.hasListener, isTrue);
      });

      test('is a no-op if the stream is already in the group', () async {
        var controller = StreamController<String>();

        // If the stream were actually listened to more than once, future
        // calls to [add] would throw [StateError]s.
        streamGroup.add(controller.stream);
        streamGroup.add(controller.stream);
        streamGroup.add(controller.stream);
      });
    });
  });

  group('remove()', () {
    group('while dormant', () {
      test("stops emitting events for a stream that's removed", () async {
        var controller = StreamController<String>();
        streamGroup.add(controller.stream);

        expect(streamGroup.stream.toList(), completion(equals(['first'])));

        controller.add('first');
        await flushMicrotasks();
        controller.add('second');

        expect(streamGroup.remove(controller.stream), completion(null));
        expect(streamGroup.close(), completes);
      });

      test('is a no-op for an unknown stream', () {
        var controller = StreamController<String>();
        expect(streamGroup.remove(controller.stream), isNull);
      });

      test('and closed closes the group when the last stream is removed',
          () async {
        var controller1 = StreamController<String>();
        var controller2 = StreamController<String>();

        streamGroup.add(controller1.stream);
        streamGroup.add(controller2.stream);
        await flushMicrotasks();

        streamGroup.close();

        streamGroup.remove(controller1.stream);
        await flushMicrotasks();

        streamGroup.remove(controller2.stream);
        await flushMicrotasks();

        expect(streamGroup.stream.toList(), completion(isEmpty));
      });
    });

    group('while listening', () {
      test("doesn't emit events from a removed stream", () {
        var controller = StreamController<String>();
        streamGroup.add(controller.stream);

        // The subscription to [controller.stream] is canceled synchronously, so
        // the first event is dropped even though it was added before the
        // removal. This is documented in [StreamGroup.remove].
        expect(streamGroup.stream.toList(), completion(isEmpty));

        controller.add('first');
        expect(streamGroup.remove(controller.stream), completion(null));
        controller.add('second');

        expect(streamGroup.close(), completes);
      });

      test("cancels the stream's subscription", () async {
        var controller = StreamController<String>();
        streamGroup.add(controller.stream);

        streamGroup.stream.listen(null);
        await flushMicrotasks();
        expect(controller.hasListener, isTrue);

        streamGroup.remove(controller.stream);
        await flushMicrotasks();
        expect(controller.hasListener, isFalse);
      });

      test('forwards cancel errors', () async {
        var controller =
            StreamController<String>(onCancel: () => throw 'error');
        streamGroup.add(controller.stream);

        streamGroup.stream.listen(null);
        await flushMicrotasks();

        expect(streamGroup.remove(controller.stream), throwsA('error'));
      });

      test('forwards cancel futures', () async {
        var completer = Completer();
        var controller =
            StreamController<String>(onCancel: () => completer.future);

        streamGroup.stream.listen(null);
        await flushMicrotasks();

        streamGroup.add(controller.stream);
        await flushMicrotasks();

        var fired = false;
        streamGroup.remove(controller.stream).then((_) => fired = true);

        await flushMicrotasks();
        expect(fired, isFalse);

        completer.complete();
        await flushMicrotasks();
        expect(fired, isTrue);
      });

      test('is a no-op for an unknown stream', () async {
        var controller = StreamController<String>();
        streamGroup.stream.listen(null);
        await flushMicrotasks();

        expect(streamGroup.remove(controller.stream), isNull);
      });

      test('and closed closes the group when the last stream is removed',
          () async {
        var done = false;
        streamGroup.stream.listen(null, onDone: () => done = true);
        await flushMicrotasks();

        var controller1 = StreamController<String>();
        var controller2 = StreamController<String>();

        streamGroup.add(controller1.stream);
        streamGroup.add(controller2.stream);
        await flushMicrotasks();

        streamGroup.close();

        streamGroup.remove(controller1.stream);
        await flushMicrotasks();
        expect(done, isFalse);

        streamGroup.remove(controller2.stream);
        await flushMicrotasks();
        expect(done, isTrue);
      });
    });
  });

  group('close()', () {
    group('while dormant', () {
      test('if there are no streams, closes the group', () {
        expect(streamGroup.close(), completes);
        expect(streamGroup.stream.toList(), completion(isEmpty));
      });

      test(
          'if there are streams, closes the group once those streams close '
          "and there's a listener", () async {
        var controller1 = StreamController<String>();
        var controller2 = StreamController<String>();

        streamGroup.add(controller1.stream);
        streamGroup.add(controller2.stream);
        await flushMicrotasks();

        streamGroup.close();

        controller1.close();
        controller2.close();
        expect(streamGroup.stream.toList(), completion(isEmpty));
      });
    });

    group('while active', () {
      test('if there are no streams, closes the group', () {
        expect(streamGroup.stream.toList(), completion(isEmpty));
        expect(streamGroup.close(), completes);
      });

      test('if there are streams, closes the group once those streams close',
          () async {
        var done = false;
        streamGroup.stream.listen(null, onDone: () => done = true);
        await flushMicrotasks();

        var controller1 = StreamController<String>();
        var controller2 = StreamController<String>();

        streamGroup.add(controller1.stream);
        streamGroup.add(controller2.stream);
        await flushMicrotasks();

        streamGroup.close();
        await flushMicrotasks();
        expect(done, isFalse);

        controller1.close();
        await flushMicrotasks();
        expect(done, isFalse);

        controller2.close();
        await flushMicrotasks();
        expect(done, isTrue);
      });
    });

    test('returns a Future that completes once all events are dispatched',
        () async {
      var events = [];
      streamGroup.stream.listen(events.add);

      var controller = StreamController<String>();
      streamGroup.add(controller.stream);
      await flushMicrotasks();

      // Add a bunch of events. Each of these will get dispatched in a
      // separate microtask, so we can test that [close] only completes once
      // all of them have dispatched.
      controller.add('one');
      controller.add('two');
      controller.add('three');
      controller.add('four');
      controller.add('five');
      controller.add('six');
      controller.close();

      await streamGroup.close();
      expect(events, equals(['one', 'two', 'three', 'four', 'five', 'six']));
    });
  });
}

/// Wait for all microtasks to complete.
Future flushMicrotasks() => Future.delayed(Duration.zero);
