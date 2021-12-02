# dispenser

[![CI](https://github.com/discord/dispenser/actions/workflows/ci.yml/badge.svg)](https://github.com/discord/dispenser/actions/workflows/ci.yml)
[![Hex.pm Version](http://img.shields.io/hexpm/v/dispenser.svg?style=flat)](https://hex.pm/packages/dispenser)
[![Hex.pm License](http://img.shields.io/hexpm/l/dispenser.svg?style=flat)](https://hex.pm/packages/dispenser)
[![HexDocs](https://img.shields.io/badge/HexDocs-Yes-blue)](https://hexdocs.pm/dispenser)

`dispenser` is an Elixir library for buffering events and sending them to multiple subscribers.

## Terminology

The terminology used in `dispenser` is similar to the terminology used in [`gen_stage`](https://hex.pm/packages/gen_stage).

`events` are pieces of data you want to send to `subscriber`s.  
A `buffer` is something that you can put `events` into.  
Multiple `subscriber`s can `ask` a `buffer` for any number of `events`.  
The amount of `events` that a `subscriber` has `ask`ed for and is waiting to receive is its `demand`.

## Overview

The basic function of the library is to accept `events` and assign them to `subscribers`.
There are two main "modes" for the `buffer`:

1. Normal Mode: There are more subscription `demand`s than there are `events` in the `buffer`.
The buffer is not filling up and events can be sent.

2. Overloaded Mode: There are more events than the subscribers can handle.
If the buffer becomes completely filled, it will drop events according to its `LimitedQueue.drop_strategy\0`.

Different uses of the library can decide how to handle these cases.
Two example `GenServer`s are implemented along with the library (see below).

## Usage / API

Append events and add subscription demand in any order, and then use `Buffer.assign_events/1` to assign events to subscribers.

```elixir
alias Dispenser.{AssignmentStrategy, Buffer}

capacity = 4
buffer = Buffer.new(AssignmentStrategy.Even, capacity, :drop_newest)
# Buffer.size(buffer) == 0
# Buffer.stats(buffer) == %{buffered: 0, demand: 0}

events = ["a", "b", "c", "d", "e"]

{buffer, dropped} = Buffer.append(buffer, events)
# dropped == 1
# Buffer.stats(buffer) == %{buffered: 4, demand: 0}

subscription_1 = make_ref()
buffer = Buffer.ask(buffer, subscription_1, 2)
# Buffer.stats(buffer) == %{buffered: 4, demand: 2}

subscription_2 = make_ref()
buffer = Buffer.ask(buffer, subscription_2, 2)
# Buffer.stats(buffer) == %{buffered: 4, demand: 4}

{buffer, assignments} = Buffer.assign_events(buffer)
# Buffer.stats(buffer) == %{buffered: 0, demand: 0}
# assignments == [{^subscription_1, ["a", "b"]}, {^subscription_2, ["c", "d"]}]
```

## Helper Modules

The library is broken into several pieces that can be implemented and tested simply.

1. `Dispenser.Demands` is an opaque module that keeps track of demands from subscribers.
2. `Dispenser.AssignmentStrategy.Even` is the assignment method we use to decide which subscribers to send a limited number of events to. It is the only assignment method implemented, but this can be extended to other methods.
3. `Dispenser.Buffer` is the main buffer that ties everything together and keeps track of demand and events.
4. `Dispenser.SubscriptionManager` can monitor `subscribers` and is a helper for building `GenServer`s that buffer events.
5. `Dispenser.MonitoredBuffer` combines the `Dispenser.Buffer` and `Dispenser.SubscriptionManager` into one module.

## `GenServer` examples

Users of this library will likely implement their own `GenServer`, but these examples are a good place to start.
Most normal uses and error cases of the `BufferServer` and `BatchingBufferServer` are covered in the tests.

### `BufferServer`

The simplest example `GenServer` is `Dispenser.Server.BufferServer`, which will accept events and send them to subscribers.

1. Normal State:
`BufferServer` will accept events and immediately send them to subscribers as evenly as it can (see `Dispenser.AssignmentStrategy.Even` and the associated tests for the assignment logic by itself in `Dispenser.AssignmentStrategy.EvenTest`).

2. Overloaded State: 
The internal buffer is filling up and the `BufferServer` will immediately send events to any subscriber who `ask`s.

Because of these two modes, the `BufferServer`'s state will either have some pending demand, or some buffered events, but never both at the same time.

When a subscribed process unsubscribes or crashes, it is removed from the `BufferServer`'s subscribers and any remaining demand for its subscriptions is canceled.

Here is a simple example:

```elixir
alias Dispenser.{AssignmentStrategy, Buffer}
alias Dispenser.Server.BufferServer

capacity = 10
buffer = Buffer.new(AssignmentStrategy.Even, capacity, :drop_oldest)
buffer_server = BufferServer.start_link(%{buffer: buffer})

:ok = BufferServer.ask(buffer_server, 1)

assert BufferServer.stats(buffer_server) == %{buffered: 0, subscribed: 1, demand: 1}

events = ["a", "b", "c", "d", "e"]
{:ok, 0} = BufferServer.append(buffer_server, events)

assert_receive {:handle_assigned_events, ^buffer_server, ["a"]}

assert BufferServer.stats(buffer_server) == %{buffered: 9, subscribed: 1, demand: 0}
```

Please see the docs for `BufferServer.ask/3` for more details on the format of the `:handle_assigned_events` message.

Please see the documentation and associated test (`Dispenser.Server.BufferServerTest`) for more details.

### `BatchingBufferServer`

`Dispenser.Server.BatchingBufferServer` is a slightly optimized improvement on `BufferServer` 
that will only send events once a minimum batch size of events has been reached.

The `BatchingBufferServer` has the two states from `BufferServer`, 
but it has a third state where it is waiting for the buffer to reach a specified size before sending out events.
This helps reduce the number of messages sent to subscribers that have demand > 1.

Please see the documentation for `BatchingBufferServer` and associated test (`Dispenser.Server.BatchingBufferServerTest`) for details.

## Running the Tests

Tests can be run by running `mix test` in the root of the library.

## Generating Documentation

This library contains a lot of internal documentation.

Documentation is available on [HexDocs](https://hexdocs.pm/dispenser), 
or you can generate the documentation from source:

```bash
$ mix deps.get
$ mix docs
```
