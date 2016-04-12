// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import "package:async/async.dart";
import "package:async/src/typed/future.dart";
import "package:test/test.dart";

import '../utils.dart';

void main() {
  group("with valid types, forwards", () {
    var wrapper;
    var errorWrapper;
    setUp(() {
      wrapper = new TypeSafeFuture<int>(new Future<Object>.value(12));

      var error = new Future<Object>.error("oh no");
      error.catchError((_) {}); // Don't let the error cause the test to fail.
      errorWrapper = new TypeSafeFuture<int>(error);
    });

    test("asStream()", () {
      expect(wrapper.asStream().toList(), completion(equals([12])));
      expect(errorWrapper.asStream().first, throwsA("oh no"));
    });

    test("catchError()", () {
      expect(
          wrapper.catchError(expectAsync((_) {}, count: 0),
              test: expectAsync((_) {}, count: 0)),
          completion(equals(12)));

      expect(errorWrapper.catchError(expectAsync((error) {
        expect(error, equals("oh no"));
        return "value";
      }), test: expectAsync((error) {
        expect(error, equals("oh no"));
        return true;
      })), completion(equals("value")));
    });

    test("then()", () {
      expect(wrapper.then((value) => value.toString()),
          completion(equals("12")));
      expect(errorWrapper.then(expectAsync((_) {}, count: 0)),
          throwsA("oh no"));
    });

    test("whenComplete()", () {
      expect(wrapper.whenComplete(expectAsync(() {})), completion(equals(12)));
      expect(errorWrapper.whenComplete(expectAsync(() {})), throwsA("oh no"));
    });

    test("timeout()", () {
      expect(wrapper.timeout(new Duration(seconds: 1)), completion(equals(12)));
      expect(errorWrapper.timeout(new Duration(seconds: 1)), throwsA("oh no"));

      expect(
          new TypeSafeFuture<int>(new Completer<Object>().future)
              .timeout(Duration.ZERO),
          throwsA(new isInstanceOf<TimeoutException>()));

      expect(
          new TypeSafeFuture<int>(new Completer<Object>().future)
              .timeout(Duration.ZERO, onTimeout: expectAsync(() => 15)),
          completion(equals(15)));
    });
  });

  group("with invalid types", () {
    var wrapper;
    setUp(() {
      wrapper = new TypeSafeFuture<int>(new Future<Object>.value("foo"));
    });

    group("throws a CastError for", () {
      test("asStream()", () {
        expect(wrapper.asStream().first, throwsCastError);
      });

      test("then()", () {
        expect(
            wrapper.then(expectAsync((_) {}, count: 0),
                onError: expectAsync((_) {}, count: 0)),
            throwsCastError);
      });

      test("whenComplete()", () {
        expect(wrapper.whenComplete(expectAsync(() {})).then((_) {}),
            throwsCastError);
      });

      test("timeout()", () {
        expect(wrapper.timeout(new Duration(seconds: 3)).then((_) {}),
            throwsCastError);

      expect(
          new TypeSafeFuture<int>(new Completer<Object>().future)
              .timeout(Duration.ZERO, onTimeout: expectAsync(() => "foo"))
              .then((_) {}),
          throwsCastError);
      });
    });

    group("doesn't throw a CastError for", () {
      test("catchError()", () {
        // catchError has a Future<dynamic> return type, so even if there's no
        // error we don't re-wrap the returned future.
        expect(wrapper.catchError(expectAsync((_) {}, count: 0)),
            completion(equals("foo")));
      });
    });
  });
}
