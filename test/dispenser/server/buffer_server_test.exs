defmodule Dispenser.Server.BufferServerTest do
  @moduledoc false
  use ExUnit.Case
  use AssertEventually, timeout: 50, interval: 1

  alias Dispenser.{Buffer, AssignmentStrategy, DummyConsumer, Fakes}
  alias Dispenser.Server.BufferServer

  def start_server(args) do
    buffer = Buffer.new(AssignmentStrategy.Even, args.capacity, :drop_oldest)
    BufferServer.start_link(%{buffer: buffer})
  end

  describe "buffer server" do
    test "accepts events" do
      {:ok, buffer} = start_server(%{capacity: 100})

      event = Fakes.create_fake_event()
      {:ok, 0} = BufferServer.append(buffer, [event])
      assert BufferServer.stats(buffer) == %{buffered: 1, subscribed: 0, demand: 0}

      events = Fakes.create_fake_events(10)
      {:ok, 0} = BufferServer.append(buffer, events)
      assert BufferServer.stats(buffer) == %{buffered: 11, subscribed: 0, demand: 0}
    end

    test "drops events when it reaches its capacity" do
      capacity = 10
      events_over_capacity = 1
      event_count = capacity + events_over_capacity
      events = Fakes.create_fake_events(event_count)

      {:ok, buffer} = start_server(%{capacity: capacity})

      {:ok, ^events_over_capacity} = BufferServer.append(buffer, events)
      assert BufferServer.stats(buffer) == %{buffered: capacity, subscribed: 0, demand: 0}

      {:ok, ^event_count} = BufferServer.append(buffer, events)
      assert BufferServer.stats(buffer) == %{buffered: capacity, subscribed: 0, demand: 0}
    end

    test "handles subscribers" do
      {:ok, buffer} = start_server(%{capacity: 10})
      :ok = BufferServer.ask(buffer, 1)
      assert BufferServer.stats(buffer) == %{buffered: 0, subscribed: 1, demand: 1}
    end

    test "handles subscribers unsubscribing" do
      {:ok, buffer} = start_server(%{capacity: 10})
      :ok = BufferServer.ask(buffer, 1)
      :ok = BufferServer.unsubscribe(buffer)
      assert BufferServer.stats(buffer) == %{buffered: 0, subscribed: 0, demand: 0}
    end

    test "unsubscribing when there is no subscriber returns an error" do
      {:ok, buffer} = start_server(%{capacity: 10})
      :ok = BufferServer.ask(buffer, self(), 1)
      :ok = BufferServer.unsubscribe(buffer, self())
      {:error, :not_subscribed} = BufferServer.unsubscribe(buffer, self())
    end

    test "handles subscribers asking for 0 events" do
      {:ok, buffer} = start_server(%{capacity: 10})
      :ok = BufferServer.ask(buffer, self(), 0)
      assert BufferServer.stats(buffer) == %{buffered: 0, subscribed: 0, demand: 0}
    end

    test "cancels demand from unsubscribed asks" do
      {:ok, buffer} = start_server(%{capacity: 10})
      {:ok, subscriber1} = DummyConsumer.start_link([])
      {:ok, subscriber2} = DummyConsumer.start_link([])
      :ok = BufferServer.ask(buffer, subscriber1, 5)
      :ok = BufferServer.ask(buffer, subscriber2, 7)
      assert BufferServer.stats(buffer) == %{buffered: 0, subscribed: 2, demand: 12}

      :ok = BufferServer.unsubscribe(buffer, subscriber1)
      assert BufferServer.stats(buffer) == %{buffered: 0, subscribed: 1, demand: 7}

      :ok = BufferServer.unsubscribe(buffer, subscriber2)
      assert BufferServer.stats(buffer) == %{buffered: 0, subscribed: 0, demand: 0}
    end

    test "sends new events immediately to satisfy demand" do
      {:ok, buffer} = start_server(%{capacity: 10})
      subscriber = self()
      :ok = BufferServer.ask(buffer, subscriber, 1)

      assert BufferServer.stats(buffer) == %{buffered: 0, subscribed: 1, demand: 1}

      events = Fakes.create_fake_events(10)
      {:ok, 0} = BufferServer.append(buffer, events)
      [first_event | _] = events

      assert_receive {:handle_assigned_events, ^buffer, events}
      assert events == [first_event]

      assert BufferServer.stats(buffer) == %{buffered: 9, subscribed: 1, demand: 0}
    end

    test "when catching up (buffer is used) sends events to new demand" do
      {:ok, buffer} = start_server(%{capacity: 10})
      subscriber = self()

      event = Fakes.create_fake_event()
      {:ok, 0} = BufferServer.append(buffer, [event])

      assert BufferServer.stats(buffer) == %{buffered: 1, subscribed: 0, demand: 0}

      :ok = BufferServer.ask(buffer, subscriber, 1)

      assert_receive {:handle_assigned_events, ^buffer, events}
      assert events == [event]

      assert BufferServer.stats(buffer) == %{buffered: 0, subscribed: 1, demand: 0}
    end

    test "sends new events evenly to multiple existing demands" do
      {:ok, buffer} = start_server(%{capacity: 10})
      {:ok, subscriber1} = DummyConsumer.start_link([])
      {:ok, subscriber2} = DummyConsumer.start_link([])

      :ok = BufferServer.ask(buffer, subscriber1, 10)
      :ok = BufferServer.ask(buffer, subscriber2, 10)

      assert BufferServer.stats(buffer) == %{buffered: 0, subscribed: 2, demand: 20}

      events = Fakes.create_fake_events(10)
      {:ok, 0} = BufferServer.append(buffer, events)

      events1 = DummyConsumer.events(subscriber1)
      events2 = DummyConsumer.events(subscriber2)
      assert length(events1) == 5
      assert length(events2) == 5
      assert Enum.all?(events1, fn event -> Enum.member?(events, event) end)
      assert Enum.all?(events2, fn event -> Enum.member?(events, event) end)
      assert not Enum.any?(events1, fn event -> Enum.member?(events2, event) end)

      assert BufferServer.stats(buffer) == %{buffered: 0, subscribed: 2, demand: 10}
    end

    test "when catching up (buffer is used) sends old events to whoever asks first" do
      {:ok, buffer} = start_server(%{capacity: 10})
      {:ok, subscriber1} = DummyConsumer.start_link([])
      {:ok, subscriber2} = DummyConsumer.start_link([])

      events = Fakes.create_fake_events(10)
      {:ok, 0} = BufferServer.append(buffer, events)

      assert BufferServer.stats(buffer) == %{buffered: 10, subscribed: 0, demand: 0}

      :ok = BufferServer.ask(buffer, subscriber1, 10)
      :ok = BufferServer.ask(buffer, subscriber2, 10)

      assert_eventually DummyConsumer.events(subscriber1) == events
      assert DummyConsumer.events(subscriber2) == []
    end

    test "subscribers are cleaned up when their process is killed" do
      {:ok, buffer} = start_server(%{capacity: 10})

      local_subscriber = self()

      {:ok, remote_subscriber1} = DummyConsumer.start_link([])
      Process.unlink(remote_subscriber1)
      remote_ref = Process.monitor(remote_subscriber1)

      {:ok, remote_subscriber2} = DummyConsumer.start_link([])

      :ok = BufferServer.ask(buffer, local_subscriber, 3)
      :ok = BufferServer.ask(buffer, remote_subscriber1, 7)
      :ok = BufferServer.ask(buffer, remote_subscriber2, 13)
      assert BufferServer.stats(buffer) == %{buffered: 0, subscribed: 3, demand: 23}

      Process.exit(remote_subscriber1, :kill)
      assert_receive {:DOWN, ^remote_ref, :process, ^remote_subscriber1, :killed}, 1000

      assert BufferServer.stats(buffer) == %{buffered: 0, subscribed: 2, demand: 16}
    end
  end
end
