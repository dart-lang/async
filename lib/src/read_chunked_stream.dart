// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async' show Stream, Future;
import 'dart:typed_data';

/// Read all chunks from [input] and return a list consisting of items from all
/// chunks.
///
/// If the maximum number of items exceeded [maxSize] this will stop reading and
/// throw [MaximumSizeExceeded].
///
/// **Example**
/// ```dart
/// import 'dart:io';
///
/// List<int> readFile(String filePath) async {
///   Stream<List<int>> fileStream = File(filePath).openRead();
///   List<int> contents = await readChunkedStream(fileStream);
///   return contents;
/// }
/// ```
///
/// If reading a byte stream of type [Stream<List<int>>] consider using
/// [readByteStream] instead.
Future<List<T>> readChunkedStream<T>(
  Stream<List<T>> input, {
  int? maxSize,
}) async {
  if (maxSize != null && maxSize < 0) {
    throw ArgumentError.value(maxSize, 'maxSize must be positive, if given');
  }

  final result = <T>[];
  await for (final chunk in input) {
    result.addAll(chunk);
    if (maxSize != null && result.length > maxSize) {
      throw MaximumSizeExceeded(maxSize);
    }
  }
  return result;
}

/// Read all bytes from [input] and return a [Uint8List] consisting of all bytes
/// from [input].
///
/// If the maximum number of bytes exceeded [maxSize] this will stop reading and
/// throw [MaximumSizeExceeded].
///
/// **Example**
/// ```dart
/// import 'dart:io';
///
/// Uint8List readFile(String filePath) async {
///   Stream<List<int>> fileStream = File(filePath).openRead();
///   Uint8List contents = await readByteStream(fileStream);
///   return contents;
/// }
/// ```
///
/// This method does the same as [readChunkedStream], except it returns a
/// [Uint8List] which can be faster when working with bytes.
///
/// **Remark** The returned [Uint8List] might be a view on a
/// larger [ByteBuffer]. Do not use [Uint8List.buffer] without taking into
/// account [Uint8List.lengthInBytes] and [Uint8List.offsetInBytes].
/// Doing so is never correct, but in many common cases an instance of
/// [Uint8List] will not be a view on a larger buffer, so such mistakes can go
/// undetected. Consider using [Uint8List.sublistView], to create subviews if
/// necessary.
Future<Uint8List> readByteStream(
  Stream<List<int>> input, {
  int? maxSize,
}) async {
  if (maxSize != null && maxSize < 0) {
    throw ArgumentError.value(maxSize, 'maxSize must be positive, if given');
  }

  final result = BytesBuilder();
  await for (final chunk in input) {
    result.add(chunk);
    if (maxSize != null && result.length > maxSize) {
      throw MaximumSizeExceeded(maxSize);
    }
  }
  return result.takeBytes();
}

/// Create a _chunked stream_ limited to the first [maxSize] items from [input].
///
/// Throws [MaximumSizeExceeded] if [input] contains more than [maxSize] items.
Stream<List<T>> limitChunkedStream<T>(
  Stream<List<T>> input, {
  int? maxSize,
}) async* {
  if (maxSize != null && maxSize < 0) {
    throw ArgumentError.value(maxSize, 'maxSize must be positive, if given');
  }

  var count = 0;
  await for (final chunk in input) {
    if (maxSize != null && maxSize - count < chunk.length) {
      yield chunk.sublist(0, maxSize - count);
      throw MaximumSizeExceeded(maxSize);
    }
    count += chunk.length;
    yield chunk;
  }
}

/// Exception thrown if [maxSize] was exceeded while reading a _chunked stream_.
///
/// This is typically thrown by [readChunkedStream] or [readByteStream].
class MaximumSizeExceeded implements Exception {
  final int maxSize;
  const MaximumSizeExceeded(this.maxSize);

  @override
  String toString() => 'Input stream exceeded the maxSize: $maxSize';
}
