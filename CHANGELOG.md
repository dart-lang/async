## 1.6.0

- Added `CancelableOperation.valueOrCancellation()`, which allows users to be
  notified when an operation is canceled elsewhere.

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

## 1.1.1

- Updated SDK version constraint to at least 1.9.0.

## 1.1.0

- ChangeLog starts here.
