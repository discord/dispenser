defmodule Dispenser.MonitoredBuffer do
  @moduledoc """
  A `MonitoredBuffer` contains most of the logic required to implement a `GenServer` that wraps a `Buffer`.
  `MonitoredBuffer` combines a `Buffer` to track events and a `SubscriptionManager` to track subscribers.
  """

  alias Dispenser.Buffer
  alias Dispenser.SubscriptionManager

  @typedoc """
  Various statistics exposed by the `MonitoredBuffer` for use by debugging and metrics.

  See `stats/1`
  """
  @type stats() :: %{
          buffered: non_neg_integer(),
          subscribed: non_neg_integer(),
          demand: non_neg_integer()
        }

  @typedoc """
  The opaque internal state of the `MonitoredBuffer`.
  """
  @opaque t(event) :: %__MODULE__{
            subscription_manager: SubscriptionManager.t(),
            buffer: Buffer.t(event, pid())
          }

  @enforce_keys [:subscription_manager, :buffer]
  defstruct [:subscription_manager, :buffer]

  @doc """
  Create a new `MonitoredBuffer` that wraps the given `Buffer`.
  """
  @spec new(Buffer.t(event, pid())) :: t(event)
        when event: any()
  def new(buffer) do
    %__MODULE__{buffer: buffer, subscription_manager: SubscriptionManager.new()}
  end

  @doc """
  Add events to the `MonitoredBuffer`.

  If the `MonitoredBuffer` reaches its capacity, events will be dropped.
  """
  @spec append(t(event), [event]) :: {t(event), dropped :: non_neg_integer()}
        when event: any()
  def append(%__MODULE__{} = state, events) do
    {buffer, dropped} = Buffer.append(state.buffer, events)
    state = %__MODULE__{state | buffer: buffer}
    {state, dropped}
  end

  @doc """
  Ask for events from the `Buffer`.

  These demands are met by calls to `assign_events/1`
  """
  @spec ask(t(event), subscriber :: pid(), demand :: non_neg_integer()) :: t(event)
        when event: any()
  def ask(%__MODULE__{} = state, subscriber, 0) when is_pid(subscriber) do
    state
  end

  def ask(%__MODULE__{} = state, subscriber, demand) when is_pid(subscriber) and demand > 0 do
    buffer = Buffer.ask(state.buffer, subscriber, demand)
    subscription_manager = SubscriptionManager.monitor(state.subscription_manager, subscriber)
    %__MODULE__{state | buffer: buffer, subscription_manager: subscription_manager}
  end

  @doc """
  Given the current events and demands, returns the events to send to each subscriber.
  """
  @spec assign_events(t(event)) :: {t(event), [{subscriber :: pid(), [event]}]}
        when event: any()
  def assign_events(%__MODULE__{} = state) do
    {buffer, assignments} = Buffer.assign_events(state.buffer)
    state = %__MODULE__{state | buffer: buffer}
    {state, assignments}
  end

  @doc """
  Handle the down signal from a monitored subscriber.
  """
  @spec down(t(event), subscriber :: pid(), reference()) ::
          {:ok, t(event)} | {:error, :wrong_ref} | {:error, :not_subscribed}
        when event: any()
  def down(%__MODULE__{} = state, subscriber, ref) do
    case SubscriptionManager.down(state.subscription_manager, subscriber, ref) do
      {:ok, subscription_manager} ->
        buffer = Buffer.delete(state.buffer, subscriber)
        state = %__MODULE__{state | buffer: buffer, subscription_manager: subscription_manager}
        {:ok, state}

      error ->
        error
    end
  end

  @doc """
  Stop monitoring and remove all demand from the given subscriber.
  """
  @spec delete(t(event), subscriber :: pid()) :: {:ok, t(event)} | {:error, :not_subscribed}
        when event: any()
  def delete(%__MODULE__{} = state, subscriber) do
    case SubscriptionManager.demonitor(state.subscription_manager, subscriber) do
      {:ok, subscription_manager} ->
        buffer = Buffer.delete(state.buffer, subscriber)
        state = %__MODULE__{state | buffer: buffer, subscription_manager: subscription_manager}
        {:ok, state}

      {:error, :not_subscribed} ->
        {:error, :not_subscribed}
    end
  end

  @doc """
  Get the number of events in the `MonitoredBuffer`.
  """
  @spec size(t(event)) :: non_neg_integer() when event: any()
  def size(%__MODULE__{} = state) do
    Buffer.size(state.buffer)
  end

  @doc """
  Get various statistics about the `MonitoredBuffer` for use when debugging and generating metrics.
  """
  @spec stats(t(event)) :: stats() when event: any()
  def stats(%__MODULE__{} = state) do
    buffer_stats = Buffer.stats(state.buffer)

    %{
      buffered: buffer_stats.buffered,
      demand: buffer_stats.demand,
      subscribed: SubscriptionManager.size(state.subscription_manager)
    }
  end
end
