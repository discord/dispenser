defmodule Dispenser.Buffer do
  @moduledoc """
  A `Dispenser.Buffer` is a buffer that manages incoming events and demand for those events.
  """
  alias Dispenser.{Demands, AssignmentStrategy}
  alias LimitedQueue

  @typedoc """
  The opaque internal state of the `Buffer`.
  """
  @opaque t(event, subscriber) :: %__MODULE__{
            events: LimitedQueue.t(event),
            demands: Demands.t(subscriber),
            assignment_strategy: AssignmentStrategy.t()
          }

  @typedoc """
  Various statistics exposed by the `Buffer` for use by debugging and metrics.

  See `stats/1`
  """
  @type stats() :: %{
          buffered: non_neg_integer(),
          demand: non_neg_integer()
        }

  @enforce_keys [:events, :demands, :assignment_strategy]
  defstruct [:events, :demands, :assignment_strategy]

  @doc """
  Create a new `Buffer` with a maximum capacity.
  """
  @spec new(AssignmentStrategy.t(), pos_integer(), LimitedQueue.drop_strategy()) ::
          t(event, subscriber)
        when event: any(), subscriber: any()
  def new(assignment_strategy, capacity, drop_strategy) when capacity > 0 do
    %__MODULE__{
      events: LimitedQueue.new(capacity, drop_strategy),
      demands: Demands.new(),
      assignment_strategy: assignment_strategy
    }
  end

  @doc """
  Add events to the `Buffer`.

  If the `Buffer` reaches its capacity, events will be dropped.
  """
  @spec append(t(event, subscriber), [event]) ::
          {t(event, subscriber), dropped :: non_neg_integer()}
        when event: any(), subscriber: any()
  def append(%__MODULE__{} = state, []) do
    {state, 0}
  end

  def append(%__MODULE__{} = state, events) when is_list(events) do
    {events, dropped} = LimitedQueue.append(state.events, events)
    state = %__MODULE__{state | events: events}
    {state, dropped}
  end

  @doc """
  Ask for events from the `Buffer`.

  These demands are met by calls to `assign_events/1`
  """
  @spec ask(t(event, subscriber), subscriber, non_neg_integer()) :: t(event, subscriber)
        when event: any(), subscriber: any()
  def ask(%__MODULE__{} = state, _subscriber, 0) do
    state
  end

  def ask(%__MODULE__{} = state, subscriber, demand) when demand > 0 do
    demands = Demands.add(state.demands, subscriber, demand)
    %__MODULE__{state | demands: demands}
  end

  @doc """
  Given the current events and demands, returns the events to send to each subscriber.
  """
  @spec assign_events(t(event, subscriber)) :: {t(event, subscriber), [{subscriber, [event]}]}
        when event: any(), subscriber: any()
  def assign_events(%__MODULE__{} = state) do
    event_count = LimitedQueue.size(state.events)
    total_demand = Demands.total(state.demands)

    if event_count == 0 or total_demand == 0 do
      {state, []}
    else
      {demands_to_meet, remaining_demands} =
        state.assignment_strategy.assign(state.demands, event_count)

      {remaining_events, assignments} = create_assignments(state.events, demands_to_meet)
      state = %__MODULE__{state | demands: remaining_demands, events: remaining_events}
      {state, assignments}
    end
  end

  @doc """
  Remove all demand from the given subscriber.
  """
  @spec delete(t(event, subscriber), subscriber) :: t(event, subscriber)
        when event: any(), subscriber: any()
  def delete(%__MODULE__{} = state, subscriber) do
    demands = Demands.delete(state.demands, subscriber)
    %__MODULE__{state | demands: demands}
  end

  @doc """
  Get the number of events in the `Buffer`.
  """
  @spec size(t(event, subscriber)) :: non_neg_integer() when event: any(), subscriber: any()
  def size(%__MODULE__{} = state) do
    LimitedQueue.size(state.events)
  end

  @doc """
  Get various statistics about the `Buffer` for use when debugging and generating metrics.
  """
  @spec stats(t(event, subscriber)) :: stats() when event: any(), subscriber: any()
  def stats(%__MODULE__{} = state) do
    %{
      buffered: LimitedQueue.size(state.events),
      demand: Demands.total(state.demands)
    }
  end

  @spec create_assignments(
          events :: LimitedQueue.t(event),
          demands :: Demands.t(subscriber)
        ) :: {remaining_events :: [event], assignments :: [{subscriber, [event]}]}
        when event: any(), subscriber: any()
  defp create_assignments(events, demands) do
    demands
    |> Demands.subscribers()
    |> Enum.reduce({events, []}, fn {subscriber, demand}, {remaining_events, assignments} ->
      {remaining_events, events_to_send} = LimitedQueue.split(remaining_events, demand)
      assignments = [{subscriber, events_to_send} | assignments]
      {remaining_events, assignments}
    end)
  end
end
