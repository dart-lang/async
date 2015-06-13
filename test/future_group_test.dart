// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/src/future_group.dart';
import 'package:test/test.dart';

void main() {
  var futureGroup;
  setUp(() {
    futureGroup = new FutureGroup();
  });

  group("with no futures", () {
    test("never completes if nothing happens", () async {
      var completed = false;
      futureGroup.future.then((_) => completed = true);

      await new Future.delayed(Duration.ZERO);
      expect(completed, isFalse);
    });

    test("completes once it's closed", () {
      expect(futureGroup.future, completion(isEmpty));
      futureGroup.close();
    });
  });

  group("with a future that already completed", () {
    test("never completes if nothing happens", () async {
      futureGroup.add(new Future.value());
      await new Future.delayed(Duration.ZERO);

      var completed = false;
      futureGroup.future.then((_) => completed = true);

      await new Future.delayed(Duration.ZERO);
      expect(completed, isFalse);
    });

    test("completes once it's closed", () async {
      futureGroup.add(new Future.value());
      await new Future.delayed(Duration.ZERO);

      expect(futureGroup.future, completes);
      futureGroup.close();
    });

    test("completes to that future's value", () {
      futureGroup.add(new Future.value(1));
      futureGroup.close();
      expect(futureGroup.future, completion(equals([1])));
    });

    test("completes to that future's error, even if it's not closed", () {
      futureGroup.add(new Future.error("error"));
      expect(futureGroup.future, throwsA("error"));
    });
  });

  test("completes once all contained futures complete", () async {
    var futureGroup = new FutureGroup();
    var completer1 = new Completer();
    var completer2 = new Completer();
    var completer3 = new Completer();

    futureGroup.add(completer1.future);
    futureGroup.add(completer2.future);
    futureGroup.add(completer3.future);
    futureGroup.close();

    var completed = false;
    futureGroup.future.then((_) => completed = true);

    completer1.complete();
    await new Future.delayed(Duration.ZERO);
    expect(completed, isFalse);

    completer2.complete();
    await new Future.delayed(Duration.ZERO);
    expect(completed, isFalse);

    completer3.complete();
    await new Future.delayed(Duration.ZERO);
    expect(completed, isTrue);
  });

  test("completes to the values of the futures in order of addition", () {
    var futureGroup = new FutureGroup();
    var completer1 = new Completer();
    var completer2 = new Completer();
    var completer3 = new Completer();

    futureGroup.add(completer1.future);
    futureGroup.add(completer2.future);
    futureGroup.add(completer3.future);
    futureGroup.close();

    // Complete the completers in reverse order to prove that that doesn't
    // affect the result order.
    completer3.complete(3);
    completer2.complete(2);
    completer1.complete(1);
    expect(futureGroup.future, completion(equals([1, 2, 3])));
  });

  test("completes to the first error to be emitted, even if it's not closed",
      () {
    var futureGroup = new FutureGroup();
    var completer1 = new Completer();
    var completer2 = new Completer();
    var completer3 = new Completer();

    futureGroup.add(completer1.future);
    futureGroup.add(completer2.future);
    futureGroup.add(completer3.future);

    completer2.completeError("error 2");
    completer1.completeError("error 1");
    expect(futureGroup.future, throwsA("error 2"));
  });
}
