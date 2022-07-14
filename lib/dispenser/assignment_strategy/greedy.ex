defmodule Dispenser.AssignmentStrategy.Greedy do
  @moduledoc """
  The `Greedy` `AssignmentStrategy` assigns events to subscribers filling their demand before considering other
  subscribers. On each call to `assign`, the order of subscribers is shuffled, meaning that in the long run
  all of the subscribers will get a roughly equal amount of work, but in the short run, work is assigned in a
  more bursty fashion.
  """

  alias Dispenser.AssignmentStrategy
  alias Dispenser.Demands

  @behaviour AssignmentStrategy

  @impl AssignmentStrategy
  def assign(%Demands{} = demands, event_count) do
    demands
    |> Demands.subscribers()
    |> Enum.shuffle()
    |> do_assign(Demands.new(), demands, event_count)
  end

  defp do_assign([], %Demands{} = assigned_demands, %Demands{} = remaining_demands, _event_count) do
    {assigned_demands, remaining_demands}
  end

  defp do_assign(
         [{subscriber, demand} | other_demands],
         %Demands{} = assigned_demands,
         %Demands{} = remaining_demands,
         event_count
       ) do
    assigned_count = min(demand, event_count)

    new_assignments = Demands.add(assigned_demands, subscriber, assigned_count)
    remaining_demands = Demands.subtract(remaining_demands, subscriber, assigned_count)

    do_assign(other_demands, new_assignments, remaining_demands, event_count - assigned_count)
  end
end
