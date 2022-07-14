defmodule Dispenser.AssignmentStrategy.GreedyTest do
  @moduledoc false
  use ExUnit.Case

  alias Dispenser.AssignmentStrategy
  alias Dispenser.{Demands, Fakes}

  describe "greedy assignment strategy" do
    test "works with a single subscriber with demand to spare" do
      subscription1 = Fakes.create_subscription()
      demands = Demands.new()
      |> Demands.add(subscription1, 10)

      {assigned_demands, remaining_demands} = AssignmentStrategy.Greedy.assign(demands, 3)

      assert Demands.get(assigned_demands, subscription1) == 3
      assert Demands.get(remaining_demands, subscription1) == 7
    end

    test "works with a single subscriber without enough demand" do
      subscription1 = Fakes.create_subscription()
      demands = Demands.new()
      |> Demands.add(subscription1, 10)

      {assigned_demands, remaining_demands} = AssignmentStrategy.Greedy.assign(demands, 15)

      # everything got its full demand assigned
      assert assigned_demands == demands
      assert remaining_demands == Demands.new()
    end

    test "works with two subscribers fully exhausted" do
      subscription1 = Fakes.create_subscription()
      subscription2 = Fakes.create_subscription()

      demands = Demands.new()
      |> Demands.add(subscription1, 10)
      |> Demands.add(subscription2, 10)

      {assigned_demands, remaining_demands} = AssignmentStrategy.Greedy.assign(demands, 25)

      # everything got its full demand assigned
      assert assigned_demands == demands
      assert remaining_demands == Demands.new()
    end

    test "works with two subscribers, satisfiable by one" do
      subscription1 = Fakes.create_subscription()
      subscription2 = Fakes.create_subscription()

      demands = Demands.new()
      |> Demands.add(subscription1, 10)
      |> Demands.add(subscription2, 10)

      {assigned_demands, remaining_demands} = AssignmentStrategy.Greedy.assign(demands, 3)

      # one of them got the partial demand
      assert Demands.get(assigned_demands, subscription1) == 3 or Demands.get(assigned_demands, subscription2) == 3
      assert Demands.size(assigned_demands) == 1

      # the remaining demands stuck around
      assert Demands.total(remaining_demands) == 17
      assert Demands.size(remaining_demands) == 2
    end

    test "works with two subscribers, satisfiable with both" do
      subscription1 = Fakes.create_subscription()
      subscription2 = Fakes.create_subscription()

      demands = Demands.new()
      |> Demands.add(subscription1, 10)
      |> Demands.add(subscription2, 10)

      {assigned_demands, remaining_demands} = AssignmentStrategy.Greedy.assign(demands, 16)

      # Both should have gotten work
      assert Demands.get(assigned_demands, subscription1) >= 6
      assert Demands.get(assigned_demands, subscription2) >= 6
      assert Demands.total(assigned_demands) == 16
      assert Demands.size(assigned_demands) == 2

      # one of them stuck around in remaining_demands
      assert Demands.total(remaining_demands) == 4
      assert Demands.size(remaining_demands) == 1
    end

    test "works with no subscribers" do
      {assigned_demands, remaining_demands} = AssignmentStrategy.Greedy.assign(Demands.new(), 10)

      assert assigned_demands == Demands.new()
      assert remaining_demands == Demands.new()
    end
  end
end
