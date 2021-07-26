// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@deprecated
library sink_base_test;

import 'dart:async';

import 'package:test/test.dart';

import 'package:async/async.dart';

void main() {
  group('CallbackEventHandler', () {
    test('no callbacks', () {
      // Nothing happens, but doesn't crash.
      var handler = CallbackEventHandler<int>();
      handler.onData(0);
      handler.onError('error', StackTrace.current);
      handler.onDone();
    });
    test('callbacks', () {
      var list = [];
      var handler = CallbackEventHandler<int>(onData: (o) {
        list.add('data:$o');
      }, onError: (e, s) {
        list.add('error:$e');
      }, onDone: () {
        list.add('done');
      });
      handler.onData(0);
      handler.onError('e1', StackTrace.current);
      handler.onData(2);
      handler.onError('e3', StackTrace.current);
      handler.onDone();
      expect(list, ['data:0', 'error:e1', 'data:2', 'error:e3', 'done']);
    });
  });

  group('MutableCallbackEventHandler', () {
    test('no initial callbacks', () {
      // Nothing happens, but doesn't crash.
      var list = [];
      var handler = MutableCallbackEventHandler<int>();
      handler.onData(0);
      handler.onError('e1', StackTrace.current);
      handler.onDone();
      expect(list, []);
      handler.dataHandler = (o) {
        list.add('data:$o');
      };
      handler.errorHandler = (e, s) {
        list.add('error:$e');
      };
      handler.doneHandler = () {
        list.add('done');
      };
      handler.onData(0);
      handler.onError('e1', StackTrace.current);
      handler.onDone();
      expect(list, ['data:0', 'error:e1', 'done']);
    });

    test('initial callbacks', () {
      var list = [];
      var list2 = [];
      var handler = MutableCallbackEventHandler<int>(onData: (o) {
        list.add('data:$o');
      }, onError: (e, s) {
        list.add('error:$e');
      }, onDone: () {
        list.add('done');
      });
      handler.onData(0);
      handler.onError('e1', StackTrace.current);
      handler.onData(2);
      handler.onError('e3', StackTrace.current);
      handler.onDone();
      expect(list, ['data:0', 'error:e1', 'data:2', 'error:e3', 'done']);
      expect(list2, []);
      handler.dataHandler = (o) {
        list2.add('data:$o');
      };
      handler.errorHandler = (e, s) {
        list2.add('error:$e');
      };
      handler.doneHandler = () {
        list2.add('done');
      };
      handler.onData(0);
      handler.onError('e1', StackTrace.current);
      handler.onDone();
      expect(list, ['data:0', 'error:e1', 'data:2', 'error:e3', 'done']);
      expect(list2, ['data:0', 'error:e1', 'done']);
    });
  });

  // We don't explicitly test [EventSinkBase] because it shares all the relevant
  // implementation with [StreamSinkBase].
  void testAdapter(EventSink<T> Function<T>(EventHandler<T>) create) {
    test('forwards add() to onAdd()', () {
      Object? value;
      var sink = create<int>(CallbackEventHandler(onError: (error, stack) {
        expect(stack, isA<StackTrace>());
        value = error;
      }));
      sink.addError('error1', StackTrace.current);
      expect(value, 'error1');
      sink.addError('error2');
      expect(value, 'error2');
    });

    test('forwards close() to onClose()', () {
      var closed = false;
      var sink = create<int>(CallbackEventHandler(onDone: () {
        closed = true;
        return null;
      }));
      sink.close();
      expect(closed, true);
    });

    test('onClose() is only invoked once', () {
      var closed = 0;
      var sink = create<int>(CallbackEventHandler(onDone: () {
        closed++;
      }));
      expect(closed, 0);
      sink.close();
      expect(closed, 1);
      sink.close();
      sink.close();
      sink.close();
      expect(closed, 1);
    });

    group("once it's closed", () {
      test('add() throws an error', () {
        var sink = create<int>(EventHandler());
        sink.close();
        expect(() => sink.add(1), throwsStateError);
      });

      test('addError() throws an error', () {
        var sink = create<int>(EventHandler());
        sink.close();
        expect(() => sink.addError('error'), throwsStateError);
      });
    });
  }

  group('EventSinkAdapter', () {
    testAdapter(<T>(handler) => EventSinkAdapter<T>(handler));
  });
  group('StreamSinkAdapter', () {
    testAdapter(<T>(handler) => StreamSinkAdapter<T>(handler));
    test('forwards addStream() to onAdd() and onError()', () {
      var list = [];
      var sink = StreamSinkAdapter<int>(CallbackEventHandler(onData: (value) {
        list.add('data:$value');
      }, onError: (error, stackTrace) {
        list.add('error:$error');
        expect(stackTrace, isA<StackTrace>());
      }));
      var controller = StreamController<int>(sync: true);
      sink.addStream(controller.stream);

      controller.add(123);
      controller.addError('error1', StackTrace.current);
      controller.add(456);
      expect(list, ['data:123', 'error:error1', 'data:456']);
    });

    test('addStream() returns once the stream closes', () async {
      var sink = StreamSinkAdapter<int>(EventHandler()); // Ignores all events.
      var controller = StreamController<int>();
      var addStreamCompleted = false;
      var addStreamTask = sink.addStream(controller.stream);
      addStreamTask.whenComplete(() {
        addStreamCompleted = true;
      });
      await pumpEventQueue();

      controller.addError('error', StackTrace.current);
      await pumpEventQueue();
      expect(addStreamCompleted, false);

      // Will close the stream and complete the future as a microtask.
      controller.close();
      await pumpEventQueue();
      expect(addStreamCompleted, true);
    });

    test('all invocations of close() return the same future', () async {
      var completer = Completer();
      var sink = StreamSinkAdapter<int>(
          CallbackEventHandler(onDone: () => completer.future));
      var close1 = sink.close();
      var close2 = sink.close();
      expect(close1, same(close2));
    });

    test('done returns the same future as close()', () async {
      var completer = Completer<void>();
      var sink = StreamSinkAdapter<int>(
          CallbackEventHandler(onDone: () => completer.future));

      var done = sink.done;
      var close = sink.close();
      expect(done, same(close));

      var doneCompleted = false;
      done.whenComplete(() => doneCompleted = true);

      await pumpEventQueue();
      expect(doneCompleted, false);

      completer.complete();
      await pumpEventQueue();
      expect(doneCompleted, true);
    });

    group('during addStream()', () {
      test('add() throws an error', () {
        var sink = StreamSinkAdapter<int>(EventHandler());
        sink.addStream(StreamController<int>().stream);
        expect(() => sink.add(1), throwsStateError);
      });

      test('addError() throws an error', () {
        var sink = StreamSinkAdapter<int>(EventHandler());
        sink.addStream(StreamController<int>().stream);
        expect(() => sink.addError('error'), throwsStateError);
      });

      test('addStream() throws an error', () {
        var sink = StreamSinkAdapter<int>(EventHandler());
        sink.addStream(StreamController<int>().stream);
        expect(() => sink.addStream(Stream.value(123)), throwsStateError);
      });

      test('close() throws an error', () {
        var sink = StreamSinkAdapter<int>(EventHandler());
        sink.addStream(StreamController<int>().stream);
        expect(() => sink.close(), throwsStateError);
      });
    });

    group("once it's closed", () {
      test('addStream() throws an error', () {
        var sink = StreamSinkAdapter<int>(EventHandler());
        expect(sink.close(), completes);
        expect(() => sink.addStream(Stream.value(123)), throwsStateError);
      });
    });
  });
}
