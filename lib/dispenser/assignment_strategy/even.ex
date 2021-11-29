defmodule Dispenser.AssignmentStrategy.Even do
  @moduledoc """
  The `Even` `AssignmentStrategy` assigns events to as many subscribers as possible, up to their demand.
  Once a subscribers has its demand satisfied, it is removed from the assignment rounds and the remaining events
  are assigned to the remaining subscribers.
  This assignment cycle continues until either all demand is satisfied or all events have been assigned.
  """

  alias Dispenser.{Demands, AssignmentStrategy}

  @behaviour AssignmentStrategy

  @typep state(subscriber) :: {
           assigned_demands :: Demands.t(subscriber),
           remaining_demands :: Demands.t(subscriber),
           event_count :: non_neg_integer()
         }

  @impl AssignmentStrategy
  def assign(demands, event_count) do
    if Demands.total(demands) <= event_count do
      # simplest case, we have enough events to satisfy all demands
      {demands, Demands.new()}
    else
      initial_demand_state = {Demands.new(), demands, event_count}
      {assigned_demands, remaining_demands, 0} = do_assign_demands(initial_demand_state)
      {assigned_demands, remaining_demands}
    end
  end

  @spec do_assign_demands(state(subscriber)) :: state(subscriber)
        when subscriber: any()
  defp do_assign_demands({_, _, 0} = state) do
    state
  end

  defp do_assign_demands(state) do
    state
    |> assign_demands_batch()
    |> do_assign_demands()
  end

  @spec assign_demands_batch(state(subscriber)) :: state(subscriber)
        when subscriber: any()
  defp assign_demands_batch(state) do
    {_, remaining_demands, event_count} = state

    subscriber_count = Demands.size(remaining_demands)

    # This batch_size is the number of events we could assign to each subscriber,
    # if every subscriber had unlimited demand.
    batch_size =
      event_count
      |> div(subscriber_count)
      |> max(1)

    # For each subscriber, try to give it batch_size events,
    # or fewer if it can't handle that many, or if we ran out of events
    remaining_demands
    |> Demands.subscribers()
    |> Enum.shuffle()
    |> Enum.reduce_while(state, fn {subscriber, demand}, state ->
      {assigned_demands, remaining_demands, event_count} = state

      # we want to send batch_size, which would be the ideal number if there were
      # unlimited events and unlimited demand...
      amount =
        batch_size
        # ...but we can not send more than the subscriber's demand...
        |> min(demand)
        # ...and if there are an uneven remainder of events on the last iteration,
        # then we must limit it to the total remaining events.
        |> min(event_count)

      assigned_demands = Demands.add(assigned_demands, subscriber, amount)
      remaining_demands = Demands.subtract(remaining_demands, subscriber, amount)

      event_count = event_count - amount
      state = {assigned_demands, remaining_demands, event_count}

      if event_count == 0 do
        {:halt, state}
      else
        {:cont, state}
      end
    end)
  end
end
