defmodule Dispenser.DummyConsumer do
  @moduledoc false
  use GenServer

  @enforce_keys [:events]
  defstruct [
    :events
  ]

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  @impl GenServer
  def init(_) do
    {:ok, %__MODULE__{events: []}}
  end

  def events(pid) do
    GenServer.call(pid, :events)
  end

  @impl GenServer
  def handle_call(:events, _from, state) do
    {:reply, state.events, state}
  end

  @impl GenServer
  def handle_info({:handle_assigned_events, _buffer, events}, state) do
    events = state.events ++ events
    state = %__MODULE__{events: events}
    {:noreply, state}
  end
end
