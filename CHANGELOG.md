## 1.10.0

* Add `DelegatingFuture.typed()`, `DelegatingStreamSubscription.typed()`,
  `DelegatingStreamConsumer.typed()`, `DelegatingSink.typed()`,
  `DelegatingEventSink.typed()`, and `DelegatingStreamSink.typed()` static
  methods. These wrap untyped instances of these classes with the correct type
  parameter, and assert the types of values as they're accessed.

* Add a `DelegatingStream` class. This is behaviorally identical to `StreamView`
  from `dart:async`, but it follows this package's naming conventions and
  provides a `DelegatingStream.typed()` static method.

* Fix all strong mode warnings and add generic method annotations.

* `new StreamQueue()`, `new SubscriptionStream()`, `new
  DelegatingStreamSubscription()`, `new DelegatingStreamConsumer()`, `new
  DelegatingSink()`, `new DelegatingEventSink()`, and `new
  DelegatingStreamSink()` now take arguments with generic type arguments (for
  example `Stream<T>`) rather than without (for example `Stream<dynamic>`).
  Passing a type that wasn't `is`-compatible with the fully-specified generic
  would already throw an error under some circumstances, so this is not
  considered a breaking change.

* `ErrorResult` now takes a type parameter.

* `Result.asError` now returns a `Result<T>`.

## 1.9.0

* Deprecate top-level libraries other than `package:async/async.dart`, which
  exports these libraries' interfaces.

* Add `Result.captureStreamTransformer`, `Result.releaseStreamTransformer`,
  `Result.captureSinkTransformer`, and `Result.releaseSinkTransformer`.

* Deprecate `CaptureStreamTransformer`, `ReleaseStreamTransformer`,
  `CaptureSink`, and `ReleaseSink`. `Result.captureStreamTransformer`,
  `Result.releaseStreamTransformer`, `Result.captureSinkTransformer`, and
  `Result.releaseSinkTransformer` should be used instead.

## 1.8.0

- Added `StreamSinkCompleter`, for creating a `StreamSink` now and providing its
  destination later as another sink.

- Added `StreamCompleter.setError`, a shortcut for emitting a single error event
  on the resulting stream.

- Added `NullStreamSink`, an implementation of `StreamSink` that discards all
  events.

## 1.7.0

- Added `SingleSubscriptionTransformer`, a `StreamTransformer` that converts a
  broadcast stream into a single-subscription stream.

## 1.6.0

- Added `CancelableOperation.valueOrCancellation()`, which allows users to be
  notified when an operation is canceled elsewhere.

- Added `StreamSinkTransformer` which transforms events before they're passed to
  a `StreamSink`, similarly to how `StreamTransformer` transforms events after
  they're emitted by a stream.

## 1.5.0

- Added `LazyStream`, which forwards to the return value of a callback that's
  only called when the stream is listened to.

## 1.4.0

- Added `AsyncMemoizer.future`, which allows the result to be accessed before
  `runOnce()` is called.

- Added `CancelableOperation`, an asynchronous operation that can be canceled.
  It can be created using a `CancelableCompleter`.

- Added `RestartableTimer`, a non-periodic timer that can be reset over and
  over.

## 1.3.0

- Added `StreamCompleter` class for creating a stream now and providing its
  events later as another stream.

- Added `StreamQueue` class which allows requesting events from a stream
  before they are avilable. It is like a `StreamIterator` that can queue
  requests.

- Added `SubscriptionStream` which creates a single-subscription stream
  from an existing stream subscription.

- Added a `ResultFuture` class for synchronously accessing the result of a
  wrapped future.

- Added `FutureGroup.onIdle` and `FutureGroup.isIdle`, which provide visibility
  into whether a group is actively waiting on any futures.

- Add an `AsyncMemoizer` class for running an asynchronous block of code exactly
  once.

- Added delegating wrapper classes for a number of core async types:
  `DelegatingFuture`, `DelegatingStreamConsumer`, `DelegatingStreamController`,
  `DelegatingSink`, `DelegatingEventSink`, `DelegatingStreamSink`, and
  `DelegatingStreamSubscription`. These are all simple wrappers that forward all
  calls to the wrapped objects. They can be used to expose only the desired
  interface for subclasses, or extended to add extra functionality.

## 1.2.0

- Added a `FutureGroup` class for waiting for a group of futures, potentially of
  unknown size, to complete.

- Added a `StreamGroup` class for merging the events of a group of streams,
  potentially of unknown size.

- Added a `StreamSplitter` class for splitting a stream into multiple new
  streams.

## 1.1.1

- Updated SDK version constraint to at least 1.9.0.

## 1.1.0

- ChangeLog starts here.
