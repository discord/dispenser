defmodule Dispenser.AssignmentStrategy do
  @moduledoc """
  A `AssignmentStrategy` is strategy to handle assigning events to subscribers to meet their demands.
  """

  alias Dispenser.Demands

  @typedoc """
  The `AssignmentStrategy` type.
  """
  @type t :: module()

  @doc """
  Given subscriber demands and a number of events, determines how to assign the events to the subscribers.

  Returns a new `assigned_demands` that contains values for assigning the events to the subscribers,
  and returns a `remaining_demands` that are left over for later when there are more events than demand.
  """
  @callback assign(demands :: Demands.t(subscriber), event_count :: non_neg_integer()) ::
              {assigned_demands :: Demands.t(subscriber),
               remaining_demands :: Demands.t(subscriber)}
            when subscriber: any()
end
