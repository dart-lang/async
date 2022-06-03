// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:async/async.dart';
import 'package:test/test.dart';

void main() {
  test("Sends initial value", () async {
    var o = ObservableValue<int>(1);
    expect(await o.updates.first, 1);
  });

  test("Sends updated value at time of listen", () async {
    var o = ObservableValue<int>(1);
    o.value = 2;
    expect(await o.updates.first, 2);
  });

  test("Sends value at time of listen, then rest", () async {
    var o = ObservableValue<int>(1);
    var f = o.updates.take(2).toList();
    o.value = 2;
    expect(await f, [1, 2]);
  });

  test("Sends value at time of listen, then rest", () async {
    var o = ObservableValue<int>(1);
    o.value = 2;
    var f = o.updates.take(2).toList();
    o.value = 3;
    expect(await f, [2, 3]);
  });

  test("Sends value at time of listen, then rest, multiple", () async {
    var o = ObservableValue<int>(1);
    var f1 = o.updates.take(3).toList();
    o.value = 2;
    var f2 = o.updates.take(2).toList();
    o.value = 3;
    expect(await f1, [1, 2, 3]);
    expect(await f2, [2, 3]);
    // Sends current value, even after existing listeners were notified.
    expect(await o.updates.first, 3);
  });

  test("Not broadcast", () {
    var o = ObservableValue<int>(1);

    expect(o.updates.isBroadcast, false);
    var expectation = 1;
    var sub = o.updates.listen(null);
    sub.onData(expectAsync1(count: 2, (v) async {
      expect(v, expectation);
      if (v == 1) expectation = 2;
      if (v == 2) sub.cancel();
      expect(await o.updates.first, 2); // Same event again.
    }));
    o.value = 2;
  });
}
