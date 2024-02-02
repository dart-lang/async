// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:test/test.dart';

void main() {
  test('Notifier.wait/notify', () async {
    final notified = Completer<void>();

    final notifier = Notifier();
    notifier.wait.then((value) => notified.complete());
    expect(notified.isCompleted, isFalse);

    notifier.notify();
    expect(notified.isCompleted, isFalse);

    await notified.future;
    expect(notified.isCompleted, isTrue);
  });

  test('Notifier.wait is never resolved', () async {
    var count = 0;

    final notifier = Notifier();
    notifier.wait.then((value) => count++);
    expect(count, 0);

    await Future.delayed(Duration.zero);
    expect(count, 0);

    notifier.notify();
    expect(count, 0);

    await Future.delayed(Duration.zero);
    expect(count, 1);

    notifier.wait.then((value) => count++);
    notifier.wait.then((value) => count++);

    await Future.delayed(Duration.zero);
    expect(count, 1);

    notifier.notify();
    expect(count, 1);

    await Future.delayed(Duration.zero);
    expect(count, 3);
  });
}
