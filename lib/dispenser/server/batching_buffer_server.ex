defmodule Dispenser.Server.BatchingBufferServer do
  @moduledoc """
  A `BatchingBufferServer` is an example `GenServer` that uses `Dispenser.Buffer`.
  It can receive events and send them to subscriber processes.

  The `BatchingBufferServer` works like `BufferServer`, but tries to minimize the number of messages
  sent to subscribers by only sending events when there is a large enough number of them.

  Subscribers can control the flow by telling the `BatchingBufferServer` how many events they want, using `ask/3`.
  See `ask/3` for more information about how events are sent to subscribers.
  """

  use GenServer

  alias Dispenser.{Buffer, MonitoredBuffer}
  alias LimitedQueue

  @typedoc """
  The arguments required to create a `BatchingBufferServer`.

  `:buffer` defines the `Buffer` used internally by the `BatchingBufferServer`.

  `:batch_size` defines the minimum batch size of events to gather before sending
  them to subscribers.

  `:max_delay` defines the maximum amount of time in milliseconds to wait for more events
  when there are fewer than `batch_size` events in the buffer.
  Once `max_delay` is reached, events will be sent to subscribers
  even if there are fewer than `batch_size` events.

  See `start_link/1`.
  """
  @type init_args(event) :: %{
          buffer: Buffer.t(event, pid()),
          batch_size: pos_integer(),
          max_delay: pos_integer()
        }

  @typedoc """
  The opaque internal state of the `BatchingBufferServer`.
  """
  @opaque t(event) :: %__MODULE__{
            buffer: MonitoredBuffer.t(event),
            batch_size: pos_integer(),
            max_delay: pos_integer(),
            # unique reference for the flush call, not a timer ref
            flush_ref: nil | reference()
          }

  @enforce_keys [:buffer, :batch_size, :max_delay, :flush_ref]
  defstruct [:buffer, :batch_size, :max_delay, :flush_ref]

  @doc """
  Start a new `BatchingBufferServer` `GenServer`.

  See `init_args/0` and `GenServer.start_link/2`
  """
  @spec start_link(init_args(event)) :: {:ok, pid()} | {:error, term()}
        when event: any()
  def start_link(init_args) do
    GenServer.start_link(__MODULE__, init_args)
  end

  @impl GenServer
  @spec init(init_args(event)) :: {:ok, t(event)}
        when event: any()
  def init(init_args) do
    monitored_buffer = MonitoredBuffer.new(init_args.buffer)

    state = %__MODULE__{
      buffer: monitored_buffer,
      batch_size: init_args.batch_size,
      max_delay: init_args.max_delay,
      flush_ref: nil
    }

    {:ok, state}
  end

  @doc """
  Add events to the `BatchingBufferServer`.

  If the buffer reaches its capacity, an error is returned with the number of events that were were dropped.
  """
  @spec append(GenServer.server(), [event]) :: {:ok, dropped :: non_neg_integer()}
        when event: any()
  def append(_server, []) do
    {:ok, 0}
  end

  def append(server, events) when is_list(events) do
    GenServer.call(server, {:append, events})
  end

  @doc """
  Unsubscribe from the `BatchingBufferServer`.
  """
  @spec unsubscribe(GenServer.server()) :: :ok | {:error, :not_subscribed}
  def unsubscribe(server) do
    unsubscribe(server, self())
  end

  @spec unsubscribe(GenServer.server(), subscriber :: pid()) :: :ok | {:error, :not_subscribed}
  def unsubscribe(server, subscriber) when is_pid(subscriber) do
    GenServer.call(server, {:unsubscribe, subscriber})
  end

  @doc """
  Ask for events from the `BatchingBufferServer`.

  Events will be delivered asynchronously to the subscribed pid in the shape of:

      {:handle_assigned_events, sender, events}

  where:

    * `sender` is the pid of this `BatchingBufferServer`.
    * `events` is a list of events that were appended to the `BatchingBufferServer`.
  """
  @spec ask(GenServer.server(), non_neg_integer()) :: :ok
  def ask(server, amount) when amount >= 0 do
    ask(server, self(), amount)
  end

  @spec ask(GenServer.server(), pid(), non_neg_integer()) :: :ok
  def ask(_server, subscriber, 0) when is_pid(subscriber) do
    :ok
  end

  def ask(server, subscriber, amount) when is_pid(subscriber) and amount > 0 do
    GenServer.cast(server, {:ask, subscriber, amount})
  end

  @doc """
  Get various statistics about the `BatchingBufferServer` for use when debugging and generating metrics.
  """
  @spec stats(GenServer.server()) :: MonitoredBuffer.stats()
  def stats(server) do
    GenServer.call(server, :stats)
  end

  @impl GenServer
  def handle_call({:append, events}, _from, %__MODULE__{} = state) do
    {buffer, dropped} = MonitoredBuffer.append(state.buffer, events)
    state = schedule_flush(%__MODULE__{state | buffer: buffer})
    {:reply, {:ok, dropped}, state}
  end

  @impl GenServer
  def handle_call({:unsubscribe, subscriber}, _from, state) do
    case MonitoredBuffer.delete(state.buffer, subscriber) do
      {:ok, buffer} ->
        state = %__MODULE__{state | buffer: buffer}
        {:reply, :ok, state}

      {:error, :not_subscribed} ->
        {:reply, {:error, :not_subscribed}, state}
    end
  end

  @impl GenServer
  def handle_call(:stats, _from, state) do
    stats = MonitoredBuffer.stats(state.buffer)
    {:reply, stats, state}
  end

  @impl GenServer
  def handle_cast({:ask, subscriber, amount}, state) do
    buffer = MonitoredBuffer.ask(state.buffer, subscriber, amount)
    state = schedule_flush(%__MODULE__{state | buffer: buffer})
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, _, pid, _}, state) do
    case MonitoredBuffer.down(state.buffer, pid, ref) do
      {:ok, buffer} ->
        {:noreply, %__MODULE__{state | buffer: buffer}}

      _error ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:flush, flush_ref}, %__MODULE__{flush_ref: flush_ref} = state) do
    state = flush(state)
    {:noreply, state}
  end

  def handle_info({:flush, _flush_ref}, %__MODULE__{} = state) do
    {:noreply, state}
  end

  @spec schedule_flush(t(event)) :: t(event)
        when event: any()
  defp schedule_flush(%__MODULE__{} = state) do
    cond do
      MonitoredBuffer.size(state.buffer) >= state.batch_size ->
        flush(state)

      state.flush_ref != nil ->
        state

      true ->
        flush_ref = make_ref()
        Process.send_after(self(), {:flush, flush_ref}, state.max_delay)
        %__MODULE__{state | flush_ref: flush_ref}
    end
  end

  @spec flush(t(event)) :: t(event)
        when event: any()
  defp flush(%__MODULE__{} = state) do
    {buffer, assignments} = MonitoredBuffer.assign_events(state.buffer)

    Enum.each(assignments, fn {subscriber, events} ->
      send_assigned_events(subscriber, events)
    end)

    %__MODULE__{state | buffer: buffer, flush_ref: nil}
  end

  @spec send_assigned_events(subscriber :: pid(), [event]) :: :ok | :noconnect
        when event: any()
  defp send_assigned_events(subscriber, []) when is_pid(subscriber) do
    :ok
  end

  defp send_assigned_events(subscriber, events) when is_pid(subscriber) and is_list(events) do
    Process.send(
      subscriber,
      {:handle_assigned_events, self(), events},
      [:noconnect]
    )
  end
end
