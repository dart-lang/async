import 'dart:async';

import 'package:test/test.dart';

import 'package:async/stream_transformers.dart';

void main() {
  test('does not emit before `trigger`', () async {
    var trigger = new StreamController();
    var values = new Stream.fromIterable([1, 2, 3]);
    var hasEmitted = false;
    values.transform(buffer(trigger.stream)).listen((_) {
      hasEmitted = true;
    });
    await new Future(() {});
    expect(hasEmitted, false);
    trigger.add(null);
    await new Future(() {});
    expect(hasEmitted, true);
  });

  test('emits immediately if trigger emits before a value', () async {
    var trigger = new StreamController();
    var values = new StreamController();
    trigger.add(null);
    var hasEmitted = false;
    values.stream.transform(buffer(trigger.stream)).listen((_) {
      hasEmitted = true;
    });
    values.add(1);
    await new Future(() {});
    expect(hasEmitted, true);
  });

  test('cancels value subscription when output canceled', () async {
    var trigger = new StreamController();
    var valuesCanceled = false;
    var values = new StreamController()
      ..onCancel = () {
        valuesCanceled = true;
      };
    var subscription =
        values.stream.transform(buffer(trigger.stream)).listen((_) {});
    subscription.cancel();
    expect(valuesCanceled, true);
  });

  test('cancels trigger subscription when output canceled', () async {
    var triggerCanceled = false;
    var trigger = new StreamController()
      ..onCancel = () {
        triggerCanceled = true;
      };
    var subscription =
        new Stream.empty().transform(buffer(trigger.stream)).listen((_) {});
    subscription.cancel();
    expect(triggerCanceled, true);
  });

  test('output stream ends when trigger ends', () async {
    var trigger = new StreamController();
    var values = new StreamController();
    var isDone = false;
    values.stream.transform(buffer(trigger.stream)).listen((_) {},
        onDone: () {
      isDone = true;
    });
    trigger.close();

    await new Future(() {});
    expect(isDone, true);
  });

  test('closes when trigger closes', () async {
    var trigger = new StreamController();
    var values = new StreamController();
    var outputClosed = false;
    values.stream.transform(buffer(trigger.stream)).listen((_) {},
        onDone: () {
      outputClosed = true;
    });
    await trigger.close();
    await new Future(() {});
    expect(outputClosed, true);
  });

  test('closes after outputting final values when source closes', () async {
    var trigger = new StreamController();
    var values = new StreamController();
    var outputClosed = false;
    values.stream.transform(buffer(trigger.stream)).listen((_) {}, onDone: () {
      outputClosed = true;
    });
    values.add(1);
    await values.close();
    expect(outputClosed, false);
    trigger.add(null);
    await new Future(() {});
    expect(outputClosed, true);
  });

  test('closes immediately if there are no pending values when source closes',
      () async {
    var trigger = new StreamController();
    var values = new StreamController();
    var outputClosed = false;
    values.stream.transform(buffer(trigger.stream)).listen((_) {}, onDone: () {
      outputClosed = true;
    });
    await values.close();
    await new Future(() {});
    expect(outputClosed, true);
  });

  test('forwards errors from trigger', () async {
    var trigger = new StreamController();
    var values = new StreamController();
    var hasError = false;
    values.stream.transform(buffer(trigger.stream)).listen((_) {}, onError: (_) {
      hasError = true;
    });
    trigger.addError(null);
    await new Future(() {});
    expect(hasError, true);
  });

  test('forwards errors from values', () async {
    var trigger = new StreamController();
    var values = new StreamController();
    var hasError = false;
    values.stream.transform(buffer(trigger.stream)).listen((_) {}, onError: (_) {
      hasError = true;
    });
    values.addError(null);
    await new Future(() {});
    expect(hasError, true);
  });
}
