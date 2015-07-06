## 1.3.0

- Added `StreamCompleter` class for creating a stream now and providing its
  events later as another stream.

- Added `StreamQueue` class which allows requesting events from a stream
  before they are avilable. It is like a `StreamIterator` that can queue
  requests.

- Added `DelegatingStreamSubscription` which is a simple wrapper around
  a `StreamSubscription` that forwards all call to the wrapped subscription.
  It can be extended to wrap extra functionality around a subscription.

- Added `SubscriptionStream` which creates a single-subscription stream
  from an existing stream subscription.

- Added `FutureGroup.onIdle` and `FutureGroup.isIdle`, which provide visibility
  into whether a group is actively waiting on any futures.

## 1.2.0

- Added a `FutureGroup` class for waiting for a group of futures, potentially of
  unknown size, to complete.

- Added a `StreamGroup` class for merging the events of a group of streams,
  potentially of unknown size.

## 1.1.1

- Updated SDK version constraint to at least 1.9.0.

## 1.1.0

- ChangeLog starts here.
