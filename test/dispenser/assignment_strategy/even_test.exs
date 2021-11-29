defmodule Dispenser.AssignmentStrategy.EvenTest do
  @moduledoc false
  use ExUnit.Case

  alias Dispenser.AssignmentStrategy
  alias Dispenser.{Demands, Fakes}

  describe "even assignment strategy" do
    test "can assign events to meet demands of one subscriber" do
      subscription1 = Fakes.create_subscription()
      demand_amount = 10
      demands = Demands.new()
      demands = Demands.add(demands, subscription1, demand_amount)

      event_count = 8

      {assigned_demands, demands} = AssignmentStrategy.Even.assign(demands, event_count)
      assert Demands.size(assigned_demands) == 1
      assert Demands.get(assigned_demands, subscription1) == event_count
      assert Demands.total(assigned_demands) == event_count

      assert Demands.size(demands) == 1
      assert Demands.get(demands, subscription1) == demand_amount - event_count
    end

    test "can evenly assign events to meet demands of multiple subscribers with even demands" do
      subscription1 = Fakes.create_subscription()
      subscription2 = Fakes.create_subscription()
      demands = Demands.new()
      demands = Demands.add(demands, subscription1, 4)
      demands = Demands.add(demands, subscription2, 4)

      event_count = 4

      {assigned_demands, demands} = AssignmentStrategy.Even.assign(demands, event_count)
      assert Demands.size(assigned_demands) == 2
      # evenly assigns
      assert Demands.get(assigned_demands, subscription1) == 2
      # evenly assigns
      assert Demands.get(assigned_demands, subscription2) == 2
      assert Demands.total(assigned_demands) == event_count

      assert Demands.get(demands, subscription1) == 2
      assert Demands.get(demands, subscription2) == 2
    end

    test "can evenly assign events to meet demands of multiple subscribers with uneven demands" do
      subscription1 = Fakes.create_subscription()
      subscription2 = Fakes.create_subscription()
      demands = Demands.new()
      demands = Demands.add(demands, subscription1, 10)
      demands = Demands.add(demands, subscription2, 2)

      event_count = 6

      {assigned_demands, demands} = AssignmentStrategy.Even.assign(demands, event_count)
      assert Demands.size(assigned_demands) == 2
      # meeting its demand
      assert Demands.get(assigned_demands, subscription2) == 2
      # evenly assigns remainder
      assert Demands.get(assigned_demands, subscription1) == 4
      assert Demands.total(assigned_demands) == event_count

      assert Demands.get(demands, subscription1) == 6
      assert Demands.get(demands, subscription2) == 0
    end

    test "can evenly assign events to meet demands of many subscribers with uneven demands" do
      subscription1 = Fakes.create_subscription()
      subscription2 = Fakes.create_subscription()
      subscription3 = Fakes.create_subscription()
      subscription4 = Fakes.create_subscription()
      demands = Demands.new()
      demands = Demands.add(demands, subscription1, 10)
      demands = Demands.add(demands, subscription2, 2)
      demands = Demands.add(demands, subscription3, 3)
      demands = Demands.add(demands, subscription4, 5)

      event_count = 13

      {assigned_demands, demands} = AssignmentStrategy.Even.assign(demands, event_count)

      assert Demands.size(assigned_demands) == 4
      # meeting its demand
      assert Demands.get(assigned_demands, subscription2) == 2
      # meeting its demand
      assert Demands.get(assigned_demands, subscription3) == 3
      # evenly assigns remainder
      assert Demands.get(assigned_demands, subscription1) == 4
      # evenly assigns remainder
      assert Demands.get(assigned_demands, subscription4) == 4
      assert Demands.total(assigned_demands) == event_count

      assert Demands.get(demands, subscription1) == 6
      assert Demands.get(demands, subscription2) == 0
      assert Demands.get(demands, subscription3) == 0
      assert Demands.get(demands, subscription4) == 1
    end

    test "can randomly assign unevenly left-over events to meet demands" do
      subscription1 = Fakes.create_subscription()
      subscription2 = Fakes.create_subscription()
      subscription3 = Fakes.create_subscription()
      subscription4 = Fakes.create_subscription()
      demands = Demands.new()
      demands = Demands.add(demands, subscription1, 2)
      demands = Demands.add(demands, subscription2, 2)
      demands = Demands.add(demands, subscription3, 2)
      demands = Demands.add(demands, subscription4, 2)

      event_count = 5

      {assigned_demands, demands} = AssignmentStrategy.Even.assign(demands, event_count)

      # should assign as follows:
      # all should get 1 event, and one random subscriber will get the extra remainder event
      assert Demands.size(assigned_demands) == 4
      assert Enum.member?(1..2, Demands.get(assigned_demands, subscription1))
      assert Enum.member?(1..2, Demands.get(assigned_demands, subscription2))
      assert Enum.member?(1..2, Demands.get(assigned_demands, subscription3))
      assert Enum.member?(1..2, Demands.get(assigned_demands, subscription4))
      assert Demands.total(assigned_demands) == event_count

      assert Demands.get(demands, subscription1) <= 1
      assert Demands.get(demands, subscription2) <= 1
      assert Demands.get(demands, subscription3) <= 1
      assert Demands.get(demands, subscription4) <= 1
      assert Demands.total(demands) == 3
    end
  end
end
