// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  group("without being canceled", () {
    CancelableCompleter completer;
    setUp(() {
      completer = CancelableCompleter(onCancel: expectAsync0(() {}, count: 0));
    });

    test("sends values to the future", () {
      expect(completer.operation.value, completion(equals(1)));
      expect(completer.isCompleted, isFalse);
      completer.complete(1);
      expect(completer.isCompleted, isTrue);
    });

    test("sends errors to the future", () {
      expect(completer.operation.value, throwsA("error"));
      expect(completer.isCompleted, isFalse);
      completer.completeError("error");
      expect(completer.isCompleted, isTrue);
    });

    test("sends values in a future to the future", () {
      expect(completer.operation.value, completion(equals(1)));
      expect(completer.isCompleted, isFalse);
      completer.complete(Future.value(1));
      expect(completer.isCompleted, isTrue);
    });

    test("sends errors in a future to the future", () {
      expect(completer.operation.value, throwsA("error"));
      expect(completer.isCompleted, isFalse);
      expect(completer.operation.isCompleted, isFalse);
      completer.complete(Future.error("error"));
      expect(completer.isCompleted, isTrue);
      expect(completer.operation.isCompleted, isTrue);
    });

    test("sends values to valueOrCancellation", () {
      expect(completer.operation.valueOrCancellation(), completion(equals(1)));
      completer.complete(1);
    });

    test("sends errors to valueOrCancellation", () {
      expect(completer.operation.valueOrCancellation(), throwsA("error"));
      completer.completeError("error");
    });

    group("throws a StateError if completed", () {
      test("successfully twice", () {
        completer.complete(1);
        expect(() => completer.complete(1), throwsStateError);
      });

      test("successfully then unsuccessfully", () {
        completer.complete(1);
        expect(() => completer.completeError("error"), throwsStateError);
      });

      test("unsuccessfully twice", () {
        expect(completer.operation.value, throwsA("error"));
        completer.completeError("error");
        expect(() => completer.completeError("error"), throwsStateError);
      });

      test("successfully then with a future", () {
        completer.complete(1);
        expect(() => completer.complete(Completer().future), throwsStateError);
      });

      test("with a future then successfully", () {
        completer.complete(Completer().future);
        expect(() => completer.complete(1), throwsStateError);
      });

      test("with a future twice", () {
        completer.complete(Completer().future);
        expect(() => completer.complete(Completer().future), throwsStateError);
      });
    });

    group("CancelableOperation.fromFuture", () {
      test("forwards values", () {
        var operation = CancelableOperation.fromFuture(Future.value(1));
        expect(operation.value, completion(equals(1)));
      });

      test("forwards errors", () {
        var operation = CancelableOperation.fromFuture(Future.error("error"));
        expect(operation.value, throwsA("error"));
      });
    });
  });

  group("when canceled", () {
    test("causes the future never to fire", () async {
      var completer = CancelableCompleter();
      completer.operation.value.whenComplete(expectAsync0(() {}, count: 0));
      completer.operation.cancel();

      // Give the future plenty of time to fire if it's going to.
      await flushMicrotasks();
      completer.complete();
      await flushMicrotasks();
    });

    test("fires onCancel", () {
      var canceled = false;
      CancelableCompleter completer;
      completer = CancelableCompleter(onCancel: expectAsync0(() {
        expect(completer.isCanceled, isTrue);
        canceled = true;
      }));

      expect(canceled, isFalse);
      expect(completer.isCanceled, isFalse);
      expect(completer.operation.isCanceled, isFalse);
      expect(completer.isCompleted, isFalse);
      expect(completer.operation.isCompleted, isFalse);
      completer.operation.cancel();
      expect(canceled, isTrue);
      expect(completer.isCanceled, isTrue);
      expect(completer.operation.isCanceled, isTrue);
      expect(completer.isCompleted, isFalse);
      expect(completer.operation.isCompleted, isFalse);
    });

    test("returns the onCancel future each time cancel is called", () {
      var completer = CancelableCompleter(onCancel: expectAsync0(() {
        return Future.value(1);
      }));
      expect(completer.operation.cancel(), completion(equals(1)));
      expect(completer.operation.cancel(), completion(equals(1)));
      expect(completer.operation.cancel(), completion(equals(1)));
    });

    test("returns a future even if onCancel doesn't", () {
      var completer = CancelableCompleter(onCancel: expectAsync0(() {}));
      expect(completer.operation.cancel(), completes);
    });

    test("doesn't call onCancel if the completer has completed", () {
      var completer =
          CancelableCompleter(onCancel: expectAsync0(() {}, count: 0));
      completer.complete(1);
      expect(completer.operation.value, completion(equals(1)));
      expect(completer.operation.cancel(), completes);
    });

    test(
        "does call onCancel if the completer has completed to an unfired "
        "Future", () {
      var completer = CancelableCompleter(onCancel: expectAsync0(() {}));
      completer.complete(Completer().future);
      expect(completer.operation.cancel(), completes);
    });

    test(
        "doesn't call onCancel if the completer has completed to a fired "
        "Future", () async {
      var completer =
          CancelableCompleter(onCancel: expectAsync0(() {}, count: 0));
      completer.complete(Future.value(1));
      await completer.operation.value;
      expect(completer.operation.cancel(), completes);
    });

    test("can be completed once after being canceled", () async {
      var completer = CancelableCompleter();
      completer.operation.value.whenComplete(expectAsync0(() {}, count: 0));
      await completer.operation.cancel();
      completer.complete(1);
      expect(() => completer.complete(1), throwsStateError);
    });

    test("fires valueOrCancellation with the given value", () {
      var completer = CancelableCompleter();
      expect(completer.operation.valueOrCancellation(1), completion(equals(1)));
      completer.operation.cancel();
    });

    test("pipes an error through valueOrCancellation", () {
      var completer = CancelableCompleter(onCancel: () {
        throw "error";
      });
      expect(completer.operation.valueOrCancellation(1), throwsA("error"));
      completer.operation.cancel();
    });

    test("valueOrCancellation waits on the onCancel future", () async {
      var innerCompleter = Completer();
      var completer =
          CancelableCompleter(onCancel: () => innerCompleter.future);

      var fired = false;
      completer.operation.valueOrCancellation().then((_) {
        fired = true;
      });

      completer.operation.cancel();
      await flushMicrotasks();
      expect(fired, isFalse);

      innerCompleter.complete();
      await flushMicrotasks();
      expect(fired, isTrue);
    });
  });

  group("asStream()", () {
    test("emits a value and then closes", () {
      var completer = CancelableCompleter();
      expect(completer.operation.asStream().toList(), completion(equals([1])));
      completer.complete(1);
    });

    test("emits an error and then closes", () {
      var completer = CancelableCompleter();
      var queue = StreamQueue(completer.operation.asStream());
      expect(queue.next, throwsA("error"));
      expect(queue.hasNext, completion(isFalse));
      completer.completeError("error");
    });

    test("cancels the completer when the subscription is canceled", () {
      var completer = CancelableCompleter(onCancel: expectAsync0(() {}));
      var sub =
          completer.operation.asStream().listen(expectAsync1((_) {}, count: 0));
      completer.operation.value.whenComplete(expectAsync0(() {}, count: 0));
      sub.cancel();
      expect(completer.isCanceled, isTrue);
    });
  });

  group("then", () {
    CancelableOperation<String> Function(int) onValue;
    CancelableOperation<String> Function(Object, StackTrace) onError;
    CancelableCompleter<int> originalCompleter;

    setUp(() {
      // Initialize all functions to ones that expect to not be called.
      onValue = expectAsync1((_) {}, count: 0, id: "onValue");
      onError = expectAsync2((e, s) {}, count: 0, id: "onError");
    });

    CancelableOperation<String> runThen() {
      originalCompleter = CancelableCompleter();
      return originalCompleter.operation.then(onValue, onError: onError);
    }

    test("onValue completes successfully", () {
      onValue = expectAsync1(
          (v) => CancelableOperation.fromFuture(Future.value(v.toString())),
          count: 1,
          id: "onValue");

      final operation = runThen();

      expect(operation.value, completion("1"));
      originalCompleter.complete(1);
    });

    test("onValue throws error", () {
      // expectAsync1 only works with functions that do not throw.
      onValue = (_) => throw "error";

      final operation = runThen();

      expect(operation.value, throwsA("error"));
      originalCompleter.complete(1);
    });

    test("onValue operation errors", () {
      onValue = expectAsync1(
          (v) => CancelableOperation.fromFuture(Future.error("error")),
          count: 1,
          id: "onValue");

      final operation = runThen();

      expect(operation.value, throwsA("error"));
      originalCompleter.complete(1);
    });

    test("original operation errors with no onError", () {
      onError = null;

      final operation = runThen();

      expect(operation.value, throwsA("error"));
      originalCompleter.completeError("error");
    });

    test("original operation errors with onError that completes successfully",
        () {
      onError = expectAsync2(
          (e, s) =>
              CancelableOperation.fromFuture(Future.value("onError caught $e")),
          count: 1,
          id: "onError");

      final operation = runThen();

      expect(operation.value, completion("onError caught error"));
      originalCompleter.completeError("error");
    });

    test("original operation errors with onError that throws", () {
      // expectAsync2 does not work with functions that throw.
      onError = (e, s) => throw "onError caught $e";

      final operation = runThen();

      expect(operation.value, throwsA("onError caught error"));
      originalCompleter.completeError("error");
    });

    test(
        "original operation errors with onError that returns operation that "
        "throws", () {
      onError = expectAsync2(
          (e, s) =>
              CancelableOperation.fromFuture(Future.error("onError caught $e")),
          count: 1,
          id: "onError");

      final operation = runThen();

      expect(operation.value, throwsA("onError caught error"));
      originalCompleter.completeError("error");
    });

    test("original operation canceled", () {
      final operation = runThen();

      expect(originalCompleter.operation.cancel(), completes);
      expect(operation.isCanceled, true);
    });

    test("onValue operation canceled", () async {
      CancelableOperation<String> onValueOperation;
      onValue =
          (_) => onValueOperation = CancelableCompleter<String>().operation;

      final operation = runThen();
      originalCompleter.complete(1);
      await pumpEventQueue();
      await onValueOperation.cancel();

      expect(operation.isCanceled, true);
    });

    test("onError operation canceled", () async {
      CancelableOperation<String> onErrorOperation;
      onError =
          (e, s) => onErrorOperation = CancelableCompleter<String>().operation;

      final operation = runThen();
      originalCompleter.completeError("error");
      await pumpEventQueue();
      await onErrorOperation.cancel();

      expect(operation.isCanceled, true);
    });

    test("canceling cancels original operation", () async {
      final operation = runThen();
      await operation.cancel();

      expect(originalCompleter.isCanceled, true);
    });

    test("canceling cancels onValue operation", () async {
      CancelableOperation<String> onValueOperation;
      onValue =
          (_) => onValueOperation = CancelableCompleter<String>().operation;

      final operation = runThen();
      originalCompleter.complete(1);
      await pumpEventQueue();
      await operation.cancel();

      expect(onValueOperation.isCanceled, true);
    });

    test("canceling cancels onError operation", () async {
      CancelableOperation<String> onErrorOperation;
      onError =
          (e, s) => onErrorOperation = CancelableCompleter<String>().operation;

      final operation = runThen();
      originalCompleter.completeError("error");
      await pumpEventQueue();
      await operation.cancel();

      expect(onErrorOperation.isCanceled, true);
    });
  });

  group("thenFuture", () {
    FutureOr<String> Function(int) onValue;
    FutureOr<String> Function(Object, StackTrace) onError;
    CancelableCompleter<int> originalCompleter;

    setUp(() {
      // Initialize all functions to ones that expect to not be called.
      onValue = expectAsync1((_) {}, count: 0, id: "onValue");
      onError = expectAsync2((e, s) {}, count: 0, id: "onError");
    });

    CancelableOperation<String> runThenFuture() {
      originalCompleter = CancelableCompleter();
      return originalCompleter.operation.thenFuture(onValue, onError: onError);
    }

    test("onValue completes successfully", () {
      onValue = expectAsync1((v) => v.toString(), count: 1, id: "onValue");

      final operation = runThenFuture();

      expect(operation.value, completion("1"));
      originalCompleter.complete(1);
    });

    test("onValue throws error", () {
      // expectAsync1 only works with functions that do not throw.
      onValue = (_) => throw "error";

      final operation = runThenFuture();

      expect(operation.value, throwsA("error"));
      originalCompleter.complete(1);
    });

    test("onValue returned Future throws error", () {
      onValue =
          expectAsync1((v) => Future.error("error"), count: 1, id: "onValue");

      final operation = runThenFuture();

      expect(operation.value, throwsA("error"));
      originalCompleter.complete(1);
    });

    test("original operation errors with no onError", () {
      onError = null;

      final operation = runThenFuture();

      expect(operation.value, throwsA("error"));
      originalCompleter.completeError("error");
    });

    test("original operation errors with onError that completes successfully",
        () {
      onError =
          expectAsync2((e, s) => "onError caught $e", count: 1, id: "onError");

      final operation = runThenFuture();

      expect(operation.value, completion("onError caught error"));
      originalCompleter.completeError("error");
    });

    test("original operation errors with onError that throws", () {
      // expectAsync2 does not work with functions that throw.
      onError = (e, s) => throw "onError caught $e";

      final operation = runThenFuture();

      expect(operation.value, throwsA("onError caught error"));
      originalCompleter.completeError("error");
    });

    test(
        "original operation errors with onError that returns Future that "
        "throws", () {
      onError = expectAsync2((e, s) => Future.error("onError caught $e"),
          count: 1, id: "onError");

      final operation = runThenFuture();

      expect(operation.value, throwsA("onError caught error"));
      originalCompleter.completeError("error");
    });

    test("original operation canceled", () {
      final operation = runThenFuture();

      expect(originalCompleter.operation.cancel(), completes);
      expect(operation.isCanceled, true);
    });

    test("canceling cancels original operation", () async {
      final operation = runThenFuture();
      await operation.cancel();

      expect(originalCompleter.isCanceled, true);
    });
  });
}
