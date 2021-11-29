defmodule Dispenser.Demands do
  @moduledoc """
  Tracks the demands of subscribers.

  Keeps a constant-time `total/1` of the overall demand.

  Used by `Buffer` to keep track of demand for events.

  Used by implementations of `Dispenser.AssignmentStrategy`
  to determine which subscribers to send to.
  """

  @typedoc """
  The current demand for one subscriber.
  """
  @type demand :: pos_integer()

  @typedoc """
  A map of all subscribers that have demand > 0, with their demands.
  """
  @type subscribers(subscriber) :: %{subscriber => demand()}

  @typedoc """
  The opaque internal state of the `Demands`.
  """
  @opaque t(subscriber) :: %__MODULE__{
            subscribers: subscribers(subscriber),
            total: non_neg_integer()
          }

  @enforce_keys [:subscribers, :total]
  defstruct [:subscribers, :total]

  @doc """
  Create a new `Demands`.
  """
  @spec new() :: t(subscriber) when subscriber: any()
  def new() do
    %__MODULE__{subscribers: %{}, total: 0}
  end

  @doc """
  Add some demand for one subscriber. A subscriber can demand as much as it wants.
  """
  @spec add(t(subscriber), subscriber, non_neg_integer()) :: t(subscriber)
        when subscriber: any()
  def add(%__MODULE__{} = state, _subscriber, 0) do
    state
  end

  def add(%__MODULE__{} = state, subscriber, amount) when amount > 0 do
    subscribers =
      Map.update(state.subscribers, subscriber, amount, fn demand -> demand + amount end)

    %__MODULE__{subscribers: subscribers, total: state.total + amount}
  end

  @doc """
  Remove some demand for one subscriber.

  Once a subscriber reaches 0 demand, it is no longer tracked by `Demands`.
  """
  @spec subtract(t(subscriber), subscriber, non_neg_integer()) :: t(subscriber)
        when subscriber: any()
  def subtract(%__MODULE__{} = state, _subscriber, 0) do
    state
  end

  def subtract(%__MODULE__{} = state, subscriber, amount) when amount > 0 do
    case Map.fetch(state.subscribers, subscriber) do
      {:ok, demand} ->
        if amount >= demand do
          delete(state, subscriber)
        else
          subscribers = Map.put(state.subscribers, subscriber, demand - amount)
          %__MODULE__{subscribers: subscribers, total: state.total - amount}
        end

      :error ->
        state
    end
  end

  @doc """
  Get the current demand for one subscriber.
  """
  @spec get(t(subscriber), subscriber) :: non_neg_integer() when subscriber: any()
  def get(%__MODULE__{} = state, subscriber) do
    Map.get(state.subscribers, subscriber, 0)
  end

  @doc """
  Get all subscribers that have demand > 0.
  """
  @spec subscribers(t(subscriber)) :: subscribers(subscriber) when subscriber: any()
  def subscribers(%__MODULE__{} = state) do
    state.subscribers
  end

  @doc """
  Remove the demand of one subscriber.
  """
  @spec delete(t(subscriber), subscriber) :: t(subscriber) when subscriber: any()
  def delete(%__MODULE__{} = state, subscriber) do
    case Map.pop(state.subscribers, subscriber) do
      {nil, _subscribers} ->
        state

      {amount, subscribers} ->
        %__MODULE__{subscribers: subscribers, total: state.total - amount}
    end
  end

  @doc """
  The total demand of all subscribers.
  """
  @spec total(t(subscriber)) :: non_neg_integer() when subscriber: any()
  def total(%__MODULE__{} = state) do
    state.total
  end

  @doc """
  The total number of subscribers that have demand > 0.
  """
  @spec size(t(subscriber)) :: non_neg_integer() when subscriber: any()
  def size(%__MODULE__{} = state) do
    map_size(state.subscribers)
  end
end
