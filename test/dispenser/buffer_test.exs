defmodule Dispenser.BufferTest do
  @moduledoc false
  use ExUnit.Case

  alias Dispenser.{Buffer, AssignmentStrategy, Fakes}

  defp create_buffer(capacity) do
    Buffer.new(AssignmentStrategy.Even, capacity, :drop_oldest)
  end

  describe "buffer" do
    test "accepts events" do
      capacity = 10
      buffer = create_buffer(capacity)
      assert Buffer.size(buffer) == 0

      events = Fakes.create_fake_events(capacity)

      {buffer, 0} = Buffer.append(buffer, events)
      assert Buffer.size(buffer) == capacity
    end

    test "drops events when it reaches its capacity" do
      capacity = 10
      events_over_capacity = 1
      event_count = capacity + events_over_capacity
      events = Fakes.create_fake_events(event_count)

      buffer = create_buffer(capacity)

      {buffer, ^events_over_capacity} = Buffer.append(buffer, events)
      assert Buffer.stats(buffer) == %{buffered: capacity, demand: 0}

      {buffer, ^event_count} = Buffer.append(buffer, events)
      assert Buffer.stats(buffer) == %{buffered: capacity, demand: 0}
    end

    test "handles asking for events" do
      buffer = create_buffer(10)
      subscription = Fakes.create_subscription()
      buffer = Buffer.ask(buffer, subscription, 1)
      assert Buffer.stats(buffer) == %{buffered: 0, demand: 1}
    end

    test "handles asking for 0 events" do
      buffer = create_buffer(10)
      subscription = Fakes.create_subscription()
      buffer = Buffer.ask(buffer, subscription, 0)
      assert Buffer.stats(buffer) == %{buffered: 0, demand: 0}
    end

    test "cancels demand from unsubscribed asks" do
      buffer = create_buffer(10)
      subscription = Fakes.create_subscription()
      buffer = Buffer.ask(buffer, subscription, 1)
      assert Buffer.stats(buffer) == %{buffered: 0, demand: 1}

      buffer = Buffer.delete(buffer, subscription)
      assert Buffer.stats(buffer) == %{buffered: 0, demand: 0}
    end

    test "assigns events to satisfy demand" do
      buffer = create_buffer(10)
      subscription = Fakes.create_subscription()
      buffer = Buffer.ask(buffer, subscription, 1)
      assert Buffer.stats(buffer) == %{buffered: 0, demand: 1}

      events = Fakes.create_fake_events(10)
      {buffer, 0} = Buffer.append(buffer, events)
      [first_event | _] = events
      assert Buffer.stats(buffer) == %{buffered: 10, demand: 1}

      {buffer, assignments} = Buffer.assign_events(buffer)
      assert assignments == [{subscription, [first_event]}]

      assert Buffer.stats(buffer) == %{buffered: 9, demand: 0}
    end

    test "assigns events in FIFO order" do
      buffer = create_buffer(10)
      subscription = Fakes.create_subscription()
      buffer = Buffer.ask(buffer, subscription, 1)
      assert Buffer.stats(buffer) == %{buffered: 0, demand: 1}

      events = Fakes.create_fake_events(10)
      [first_event | events] = events
      {buffer, 0} = Buffer.append(buffer, [first_event])
      assert Buffer.stats(buffer) == %{buffered: 1, demand: 1}

      {buffer, 0} = Buffer.append(buffer, events)
      assert Buffer.stats(buffer) == %{buffered: 10, demand: 1}

      {buffer, assignments} = Buffer.assign_events(buffer)
      assert assignments == [{subscription, [first_event]}]

      assert Buffer.stats(buffer) == %{buffered: 9, demand: 0}
    end

    test "handles assign events call when there are no subscriptions" do
      buffer = create_buffer(10)

      events = Fakes.create_fake_events(10)
      {buffer, 0} = Buffer.append(buffer, events)
      assert Buffer.stats(buffer) == %{buffered: 10, demand: 0}

      {buffer, assignments} = Buffer.assign_events(buffer)
      assert assignments == []

      assert Buffer.stats(buffer) == %{buffered: 10, demand: 0}
    end

    test "handles assign events call when there are no events" do
      buffer = create_buffer(10)
      subscription = Fakes.create_subscription()
      buffer = Buffer.ask(buffer, subscription, 1)
      assert Buffer.stats(buffer) == %{buffered: 0, demand: 1}

      {buffer, assignments} = Buffer.assign_events(buffer)
      assert assignments == []

      assert Buffer.stats(buffer) == %{buffered: 0, demand: 1}
    end
  end
end
