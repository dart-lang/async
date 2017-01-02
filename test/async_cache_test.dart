// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:test/test.dart';

void main() {
  AsyncCache<String> cache;
  DateTime time;

  setUp(() {
    // Create a cache that is fresh for an hour starting at 1/1/17 @ 12:30PM.
    cache = new AsyncCache<String>(const Duration(hours: 1), now: () => time);
    time = new DateTime(2017, 1, 1, 12, 30);
  });

  test('should fetch via a callback when no cache exists', () async {
    var callback = expectAsync0/*<Future<String>>*/(() async => 'Expensive');
    expect(await cache.fetch(callback), 'Expensive');
  });

  test('should not fetch via callback when a cache exists', () async {
    Future<String> doNotCall() async => 'Should not have been invoked...';
    await cache.fetch(() async => 'Expensive');
    expect(await cache.fetch(doNotCall), 'Expensive');
  });

  test('should not fetch via callback when a future is in-flight', () async {
    // No actual caching is done, just avoid duplicate requests.
    cache = new AsyncCache<String>.ephemeral(now: () => time);

    var completer = new Completer<String>();
    Future<String> doNotCall() async => 'Should not have been invoked...';
    Future<String> callCompleter() => completer.future;
    expect(cache.fetch(callCompleter), completion('Expensive'));
    expect(cache.fetch(doNotCall), completion('Expensive'));
    await completer.complete('Expensive');
  });

  test('should fetch via a callback again when cache expires', () async {
    var timesCalled = 0;
    Future<String> call() async => 'Called ${++timesCalled}';
    expect(await cache.fetch(call), 'Called 1');
    expect(await cache.fetch(call), 'Called 1', reason: 'Cache still fresh');

    time = time.add(const Duration(hours: 1) - const Duration(seconds: 1));
    expect(await cache.fetch(call), 'Called 1', reason: 'Cache still fresh');

    time = time.add(const Duration(seconds: 1));
    expect(await cache.fetch(call), 'Called 2');
    expect(await cache.fetch(call), 'Called 2', reason: 'Cache fresh again');

    time = time.add(const Duration(hours: 1));
    expect(await cache.fetch(call), 'Called 3');
  });

  test('should fetch via a callback when manually invalidated', () async {
    var timesCalled = 0;
    Future<String> call() async => 'Called ${++timesCalled}';
    expect(await cache.fetch(call), 'Called 1');
    await cache.invalidate();
    expect(await cache.fetch(call), 'Called 2');
    await cache.invalidate();
    expect(await cache.fetch(call), 'Called 3');
  });

  test('should fetch a stream via a callback', () async {
    var callback = expectAsync0/*<Stream<String>>*/(() {
      return new Stream.fromIterable(['1', '2', '3']);
    });
    expect(await cache.fetchStream(callback).toList(), ['1', '2', '3']);
  });

  test('should not fetch stream via callback when a cache exists', () async {
    Stream<String> doNotCall() {
      return new Stream.fromIterable(['SHOULD', 'NOT', 'SHOW', 'UP']);
    }

    await cache.fetchStream(() async* {
      yield '1';
      yield '2';
      yield '3';
    }).toList();
    expect(await cache.fetchStream(doNotCall).toList(), ['1', '2', '3']);
  });

  test('should not fetch stream via callback when request in flight', () async {
    // Unlike the above test, we want to verify that we don't make multiple
    // calls if a cache is being filled currently, and instead wait for that
    // cache to be completed.
    var controller = new StreamController<String>();
    Stream<String> call() => controller.stream;
    expect(cache.fetchStream(call).toList(), completion(['1', '2', '3']));
    controller.add('1');
    controller.add('2');
    await new Future.value();
    expect(cache.fetchStream(call).toList(), completion(['1', '2', '3']));
    controller.add('3');
    await controller.close();
  });

  test('should fetch stream via a callback again when cache expires', () async {
    var timesCalled = 0;
    Stream<String> call() {
      return new Stream<String>.fromIterable(['Called ${++timesCalled}']);
    }

    expect(await cache.fetchStream(call).toList(), ['Called 1']);
    expect(await cache.fetchStream(call).toList(), ['Called 1'],
        reason: 'Cache still fresh');

    time = time.add(const Duration(hours: 1) - const Duration(seconds: 1));
    expect(await cache.fetchStream(call).toList(), ['Called 1'],
        reason: 'Cache still fresh');

    time = time.add(const Duration(seconds: 1));
    expect(await cache.fetchStream(call).toList(), ['Called 2']);
    expect(await cache.fetchStream(call).toList(), ['Called 2'],
        reason: 'Cache fresh again');

    time = time.add(const Duration(hours: 1));
    expect(await cache.fetchStream(call).toList(), ['Called 3']);
  });

  test('should fetch via a callback when manually invalidated', () async {
    var timesCalled = 0;
    Stream<String> call() {
      return new Stream<String>.fromIterable(['Called ${++timesCalled}']);
    }
    expect(await cache.fetchStream(call).toList(), ['Called 1']);
    await cache.invalidate();
    expect(await cache.fetchStream(call).toList(), ['Called 2']);
    await cache.invalidate();
    expect(await cache.fetchStream(call).toList(), ['Called 3']);
  });
}
