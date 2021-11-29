defmodule Dispenser.SubscriptionManager do
  @moduledoc """
  `SubscriptionManager` handles monitoring and demonitoring subscribers
  """

  @typedoc """
  The opaque internal state of the `SubscriptionManager`.
  """
  @opaque t() :: %__MODULE__{
            subscribers: %{pid() => reference()}
          }

  @enforce_keys [:subscribers]
  defstruct subscribers: %{}

  @spec new() :: t()
  def new() do
    %__MODULE__{subscribers: %{}}
  end

  @doc """
  Monitor the given pid using `Process.monitor/1`.
  Callers must handle the :DOWN message from this pid.
  """
  @spec monitor(t(), pid()) :: t()
  def monitor(%__MODULE__{} = state, subscriber) when is_pid(subscriber) do
    if Map.has_key?(state.subscribers, subscriber) do
      state
    else
      ref = Process.monitor(subscriber)
      subscribers = Map.put(state.subscribers, subscriber, ref)
      %__MODULE__{state | subscribers: subscribers}
    end
  end

  @doc """
  Stop monitoring the given subscriber.
  """
  @spec demonitor(t(), pid()) :: {:ok, t()} | {:error, :not_subscribed}
  def demonitor(%__MODULE__{} = state, subscriber) when is_pid(subscriber) do
    case Map.fetch(state.subscribers, subscriber) do
      {:ok, ref} ->
        Process.demonitor(ref, [:flush])
        subscribers = Map.delete(state.subscribers, subscriber)
        state = %__MODULE__{state | subscribers: subscribers}
        {:ok, state}

      _ ->
        {:error, :not_subscribed}
    end
  end

  @doc """
  Handle the down signal from a monitored subscriber.
  """
  @spec down(t(), pid(), reference()) ::
          {:ok, t()} | {:error, :wrong_ref} | {:error, :not_subscribed}
  def down(%__MODULE__{} = state, subscriber, ref)
      when is_pid(subscriber) and is_reference(ref) do
    case Map.fetch(state.subscribers, subscriber) do
      {:ok, ^ref} ->
        Process.demonitor(ref, [:flush])
        subscribers = Map.delete(state.subscribers, subscriber)
        state = %__MODULE__{state | subscribers: subscribers}
        {:ok, state}

      {:ok, _ref} ->
        {:error, :wrong_ref}

      _ ->
        {:error, :not_subscribed}
    end
  end

  @doc """
  Get the number of currently monitored subscribers.
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{} = state) do
    map_size(state.subscribers)
  end
end
