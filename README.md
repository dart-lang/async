Contains utility classes in the style of `dart:async` to work with asynchronous
computations.

### Zipping streams

The `StreamZip` class can combine several streams of events into a single stream
of tuples of events.

### Results

The package introduces a `Result` class that can hold either a value or an
error. It allows capturing an asynchronous computation which can give either a
value or an error, into an asynchronous computation that always gives a `Result`
value, where errors can be treated as data. It also allows releasing the
`Result` back into an asynchronous computation.
