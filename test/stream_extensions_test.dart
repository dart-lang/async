// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE filevents.

import 'dart:async';

import 'package:async/async.dart';
import 'package:test/test.dart';

void main() {
  group('.slices', () {
    test('empty', () {
      expect(Stream.empty().slices(1).toList(), completion(equals([])));
    });

    test('with the same length as the iterable', () {
      expect(
          Stream.fromIterable([1, 2, 3]).slices(3).toList(),
          completion(equals([
            [1, 2, 3]
          ])));
    });

    test('with a longer length than the iterable', () {
      expect(
          Stream.fromIterable([1, 2, 3]).slices(5).toList(),
          completion(equals([
            [1, 2, 3]
          ])));
    });

    test('with a shorter length than the iterable', () {
      expect(
          Stream.fromIterable([1, 2, 3]).slices(2).toList(),
          completion(equals([
            [1, 2],
            [3]
          ])));
    });

    test('with length divisible by the iterable\'s', () {
      expect(
          Stream.fromIterable([1, 2, 3, 4]).slices(2).toList(),
          completion(equals([
            [1, 2],
            [3, 4]
          ])));
    });

    test('refuses negative length', () {
      expect(() => Stream.fromIterable([1]).slices(-1), throwsRangeError);
    });

    test('refuses length 0', () {
      expect(() => Stream.fromIterable([1]).slices(0), throwsRangeError);
    });
  });
}
