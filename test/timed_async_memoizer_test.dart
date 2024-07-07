// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:test/test.dart';

void main() {
  group('TimedAsyncMemoizer Tests', () {
    final delay = const Duration(milliseconds: 10);
    late TimedAsyncMemoizer memoizer;

    setUp(() {
      memoizer = TimedAsyncMemoizer(
        expiryDuration: delay,
      );
    });

    test('isExpired returns true when run() is not called', () {
      expect(memoizer.isExpired, true);
    });

    test(
      'isExpired returns false when run() is called and not expired',
      () async {
        await memoizer.run(() => Future.value(1));
        expect(memoizer.isExpired, false);
      },
    );

    test(
      'isExpired returns true when run() is called and expired',
      () async {
        await memoizer.run(() => Future.value(1));
        await Future.delayed(delay);
        expect(memoizer.isExpired, true);
      },
    );

    test('runs function once when not expired', () async {
      var count = 0;
      void c() {
        count++;
      }

      await memoizer.run(c);
      await memoizer.run(c);
      await memoizer.run(c);
      await memoizer.run(c);
      await memoizer.run(c);

      expect(count, 1);
    });

    test('runs function multiple times when expired', () async {
      var count = 0;
      void c() {
        count++;
      }

      await memoizer.run(c);
      await Future.delayed(delay);
      await memoizer.run(c);

      expect(count, 2);
    });

    test('returns the result of the function', () async {
      expect(memoizer.run(() => 'value'), completion(equals('value')));
      expect(memoizer.run(() {}), completion(equals('value')));
    });

    test('returns new result when expired', () async {
      expect(memoizer.run(() => 'value'), completion(equals('value')));
      await Future.delayed(delay);
      expect(memoizer.run(() => 'value2'), completion(equals('value2')));
    });

    test('returns thrown error of the function', () async {
      expect(memoizer.run(() async => throw 'error'), throwsA('error'));
      expect(memoizer.run(() {}), throwsA('error'));
    });

    test('returns new thrown error when expired', () async {
      expect(memoizer.run(() async => throw 'error'), throwsA('error'));
      await Future.delayed(delay);
      expect(memoizer.run(() async => throw 'error2'), throwsA('error2'));
    });
  });
}
