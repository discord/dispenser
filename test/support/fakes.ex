defmodule Dispenser.Fakes do
  @moduledoc false

  @spec create_subscription() :: any()
  def create_subscription() do
    make_ref()
  end

  @spec create_fake_event() :: any()
  @spec create_fake_event(non_neg_integer()) :: any()
  def create_fake_event(number \\ 0) do
    %{test_event: true, number: number, unique_ref: make_ref()}
  end

  @spec create_fake_events(count :: non_neg_integer()) :: [any()]
  def create_fake_events(count) do
    do_create_fake_events(count, 0, [])
    |> Enum.reverse()
  end

  ## Private Functions

  @spec do_create_fake_events(non_neg_integer(), non_neg_integer(), [event]) :: [event]
        when event: any()
  defp do_create_fake_events(0, _start_number, events) do
    events
  end

  defp do_create_fake_events(count, start_number, events) do
    events = [create_fake_event(start_number) | events]
    do_create_fake_events(count - 1, start_number + 1, events)
  end
end
