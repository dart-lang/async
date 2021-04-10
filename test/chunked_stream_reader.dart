// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';
import 'package:test/test.dart';

import 'package:async/async.dart';

Stream<List<T>> _chunkedStream<T>(List<List<T>> chunks) async* {
  for (final chunk in chunks) {
    yield chunk;
  }
}

Stream<List<T>> _chunkedStreamWithError<T>(List<List<T>> chunks) async* {
  for (final chunk in chunks) {
    yield chunk;
  }

  throw StateError('test generated error');
}

Future<List<T>> _readChunkedStream<T>(Stream<List<T>> input) async {
  final result = <T>[];
  await for (final chunk in input) {
    result.addAll(chunk);
  }
  return result;
}

void main() {
  test('readChunk() -- chunk in given size', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.readChunk(3), equals(['a', 'b', 'c']));
    expect(await s.readChunk(2), equals(['1', '2']));
    expect(await s.readChunk(1), equals([]));
  });

  test('readChunk() propagates stream error', () async {
    final s = ChunkedStreamReader(_chunkedStreamWithError([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.readChunk(3), equals(['a', 'b', 'c']));
    expect(() async => await s.readChunk(3), throwsStateError);
  });

  test('readChunk() -- chunk in given size', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.readChunk(2), equals(['a', 'b']));
    expect(await s.readChunk(3), equals(['c', '1', '2']));
    expect(await s.readChunk(1), equals([]));
  });

  test('readChunk() -- chunks one item at the time', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.readChunk(1), equals(['a']));
    expect(await s.readChunk(1), equals(['b']));
    expect(await s.readChunk(1), equals(['c']));
    expect(await s.readChunk(1), equals(['1']));
    expect(await s.readChunk(1), equals(['2']));
    expect(await s.readChunk(1), equals([]));
  });

  test('readChunk() -- until exact end of stream', () async {
    final stream = Stream.fromIterable(Iterable.generate(
      10,
      (_) => Uint8List(512),
    ));

    final s = ChunkedStreamReader(stream);
    while (true) {
      final c = await s.readBytes(1024);
      if (c.isEmpty) {
        break;
      }
    }
  });

  test('readChunk() -- one big chunk', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.readChunk(6), equals(['a', 'b', 'c', '1', '2']));
  });

  test('readStream() propagates stream error', () async {
    final s = ChunkedStreamReader(_chunkedStreamWithError([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.readChunk(3), equals(['a', 'b', 'c']));
    final substream = s.readStream(3);
    final subChunkedStreamReader = ChunkedStreamReader(substream);
    expect(() async => await subChunkedStreamReader.readChunk(3),
        throwsStateError);
  });

  test('readStream() + _readChunkedStream()', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await _readChunkedStream(s.readStream(5)),
        equals(['a', 'b', 'c', '1', '2']));
    expect(await s.readChunk(1), equals([]));
  });

  test('(readStream() + _readChunkedStream()) x 2', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await _readChunkedStream(s.readStream(2)), equals(['a', 'b']));
    expect(await _readChunkedStream(s.readStream(3)), equals(['c', '1', '2']));
  });

  test('readStream() + _readChunkedStream() -- past end', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await _readChunkedStream(s.readStream(6)),
        equals(['a', 'b', 'c', '1', '2']));
    expect(await s.readChunk(1), equals([]));
  });

  test('readChunk() readStream() + _readChunkedStream() readChunk()', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.readChunk(1), equals(['a']));
    expect(await _readChunkedStream(s.readStream(3)), equals(['b', 'c', '1']));
    expect(await s.readChunk(2), equals(['2']));
  });

  test(
      'readChunk() StreamIterator(readStream()).cancel() readChunk() '
      '-- one item at the time', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.readChunk(1), equals(['a']));
    final i = StreamIterator(s.readStream(3));
    expect(await i.moveNext(), isTrue);
    await i.cancel();
    expect(await s.readChunk(1), equals(['2']));
    expect(await s.readChunk(1), equals([]));
  });

  test(
      'readChunk() StreamIterator(readStream()) readChunk() '
      '-- one item at the time', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.readChunk(1), equals(['a']));
    final i = StreamIterator(s.readStream(3));
    expect(await i.moveNext(), isTrue);
    expect(i.current, equals(['b', 'c']));
    expect(await i.moveNext(), isTrue);
    expect(i.current, equals(['1']));
    expect(await i.moveNext(), isFalse);
    expect(await s.readChunk(1), equals(['2']));
    expect(await s.readChunk(1), equals([]));
  });

  test('readStream() x 2', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(
        await s.readStream(2).toList(),
        equals([
          ['a', 'b']
        ]));
    expect(
        await s.readStream(3).toList(),
        equals([
          ['c'],
          ['1', '2']
        ]));
  });

  test(
      'readChunk() StreamIterator(readStream()).cancel() readChunk() -- '
      'cancellation after reading', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.readChunk(1), equals(['a']));
    final i = StreamIterator(s.readStream(3));
    expect(await i.moveNext(), isTrue);
    await i.cancel();
    expect(await s.readChunk(1), equals(['2']));
    expect(await s.readChunk(1), equals([]));
  });

  test(
      'readChunk() StreamIterator(readStream()).cancel() readChunk() -- '
      'cancellation after reading (2)', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2', '3'],
      ['4', '5', '6']
    ]));
    expect(await s.readChunk(1), equals(['a']));
    final i = StreamIterator(s.readStream(6));
    expect(await i.moveNext(), isTrue);
    await i.cancel();
    expect(await s.readChunk(1), equals(['5']));
    expect(await s.readChunk(1), equals(['6']));
  });

  test(
      'readChunk() StreamIterator(readStream()) readChunk() -- '
      'not cancelling produces StateError', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.readChunk(1), equals(['a']));
    final i = StreamIterator(s.readStream(3));
    expect(await i.moveNext(), isTrue);
    expect(() async => await s.readChunk(1), throwsStateError);
  });

  test(
      'readChunk() StreamIterator(readStream()) readChunk() -- '
      'not cancelling produces StateError (2)', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.readChunk(1), equals(['a']));

    /// ignore: unused_local_variable
    final i = StreamIterator(s.readStream(3));
    expect(() async => await s.readChunk(1), throwsStateError);
  });

  test(
      'readChunk() readStream() that ends with first chunk + '
      '_readChunkedStream() readChunk()', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.readChunk(1), equals(['a']));
    expect(
        await s.readStream(2).toList(),
        equals([
          ['b', 'c']
        ]));
    expect(await s.readChunk(3), equals(['1', '2']));
  });

  test(
      'readChunk() readStream() that ends with first chunk + drain() '
      'readChunk()', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
    ]));
    expect(await s.readChunk(1), equals(['a']));
    final sub = s.readStream(2);
    await sub.drain();
    expect(await s.readChunk(3), equals(['1', '2']));
  });

  test(
      'readChunk() readStream() that ends with second chunk + '
      '_readChunkedStream() readChunk()', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
      ['3', '4']
    ]));
    expect(await s.readChunk(1), equals(['a']));
    expect(
        await s.readStream(4).toList(),
        equals([
          ['b', 'c'],
          ['1', '2']
        ]));
    expect(await s.readChunk(3), equals(['3', '4']));
  });

  test(
      'readChunk() readStream() that ends with second chunk + '
      'drain() readChunk()', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
      ['3', '4'],
    ]));
    expect(await s.readChunk(1), equals(['a']));
    final substream = s.readStream(4);
    await substream.drain();
    expect(await s.readChunk(3), equals(['3', '4']));
  });

  test(
      'readChunk() readStream() readChunk() before '
      'draining substream produces StateError', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
      ['3', '4'],
    ]));
    expect(await s.readChunk(1), equals(['a']));
    // ignore: unused_local_variable
    final substream = s.readStream(4);
    expect(() async => await s.readChunk(3), throwsStateError);
  });

  test('creating two substreams simultaneously causes a StateError', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b', 'c'],
      ['1', '2'],
      ['3', '4'],
    ]));
    expect(await s.readChunk(1), equals(['a']));
    // ignore: unused_local_variable
    final substream = s.readStream(4);
    expect(() async {
      //ignore: unused_local_variable
      final substream2 = s.readStream(3);
    }, throwsStateError);
  });

  test('nested ChunkedStreamReader', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      ['a', 'b'],
      ['1', '2'],
      ['3', '4'],
    ]));
    expect(await s.readChunk(1), equals(['a']));
    final substream = s.readStream(4);
    final nested = ChunkedStreamReader(substream);
    expect(await nested.readChunk(2), equals(['b', '1']));
    expect(await nested.readChunk(3), equals(['2', '3']));
    expect(await nested.readChunk(2), equals([]));
    expect(await s.readChunk(1), equals(['4']));
  });

  test('ChunkedStreamReaderByteStreamExt', () async {
    final s = ChunkedStreamReader(_chunkedStream([
      [1, 2, 3],
      [4],
    ]));
    expect(await s.readBytes(1), equals([1]));
    expect(await s.readBytes(1), isA<Uint8List>());
    expect(await s.readBytes(1), equals([3]));
    expect(await s.readBytes(1), equals([4]));
    expect(await s.readBytes(1), equals([]));
  });

  test('cancel while readChunk() is pending', () async {
    final s = ChunkedStreamReader(() async* {
      yield [1, 2, 3];
      // This will hang forever, so we will call cancel()
      await Completer().future;
      yield [4]; // this should never be reachable
      fail('unreachable!');
    }());

    expect(await s.readBytes(2), equals([1, 2]));

    final future = s.readChunk(2);

    // Wait a tiny bit and cancel
    await Future.microtask(() => null);
    s.cancel();

    expect(await future, hasLength(lessThan(2)));
  });

  test('cancel while readStream() is pending', () async {
    final s = ChunkedStreamReader(() async* {
      yield [1, 2, 3];
      // This will hang forever, so we will call cancel()
      await Completer().future;
      yield [4]; // this should never be reachable
      fail('unreachable!');
    }());

    expect(await collectBytes(s.readStream(2)), equals([1, 2]));

    final stream = s.readStream(2);

    // Wait a tiny bit and cancel
    await Future.microtask(() => null);
    s.cancel();

    expect(await collectBytes(stream), hasLength(lessThan(2)));
  });
}
