defmodule Dispenser.DemandsTest do
  @moduledoc false
  use ExUnit.Case

  alias Dispenser.{Demands, Fakes}

  describe "demands" do
    test "can be created" do
      demands = Demands.new()
      assert Demands.size(demands) == 0
    end

    test "can be added" do
      demands = Demands.new()
      subscription1 = Fakes.create_subscription()
      demands = Demands.add(demands, subscription1, 1)
      assert Demands.size(demands) == 1
      assert Demands.get(demands, subscription1) == 1
      assert Demands.total(demands) == 1

      subscription2 = Fakes.create_subscription()
      demands = Demands.add(demands, subscription2, 100)
      assert Demands.size(demands) == 2
      assert Demands.get(demands, subscription2) == 100
      assert Demands.total(demands) == 101
    end

    test "0 demands can be added" do
      demands = Demands.new()
      subscription1 = Fakes.create_subscription()
      demands = Demands.add(demands, subscription1, 0)
      assert Demands.size(demands) == 0
      assert Demands.get(demands, subscription1) == 0
      assert Demands.total(demands) == 0
    end

    test "can be subtracted" do
      demands = Demands.new()
      subscription1 = Fakes.create_subscription()
      demands = Demands.add(demands, subscription1, 101)
      demands = Demands.subtract(demands, subscription1, 1)
      assert Demands.size(demands) == 1
      assert Demands.get(demands, subscription1) == 100
      assert Demands.total(demands) == 100

      subscription2 = Fakes.create_subscription()
      demands = Demands.add(demands, subscription2, 1001)
      demands = Demands.subtract(demands, subscription2, 1)
      assert Demands.size(demands) == 2
      assert Demands.get(demands, subscription2) == 1000
      assert Demands.total(demands) == 1100
    end

    test "0 demands can be subtracted" do
      demands = Demands.new()
      subscription1 = Fakes.create_subscription()
      demands = Demands.add(demands, subscription1, 100)
      demands = Demands.subtract(demands, subscription1, 0)
      assert Demands.size(demands) == 1
      assert Demands.get(demands, subscription1) == 100
      assert Demands.total(demands) == 100
    end

    test "can be subtracted for subscribers with no demands" do
      demands = Demands.new()
      subscription1 = Fakes.create_subscription()
      demands = Demands.subtract(demands, subscription1, 1)
      assert Demands.size(demands) == 0
      assert Demands.get(demands, subscription1) == 0
      assert Demands.total(demands) == 0
    end

    test "that go below 0 are treated as 0" do
      demands = Demands.new()
      subscription1 = Fakes.create_subscription()
      demands = Demands.add(demands, subscription1, 100)
      demands = Demands.subtract(demands, subscription1, 1000)
      assert Demands.size(demands) == 0
      assert Demands.get(demands, subscription1) == 0
      assert Demands.total(demands) == 0
    end

    test "can be deleted" do
      demands = Demands.new()
      subscription1 = Fakes.create_subscription()
      demands = Demands.add(demands, subscription1, 100)

      subscription2 = Fakes.create_subscription()
      demands = Demands.add(demands, subscription2, 1000)
      assert Demands.size(demands) == 2
      assert Demands.get(demands, subscription1) == 100
      assert Demands.get(demands, subscription2) == 1000
      assert Demands.total(demands) == 1100

      demands = Demands.delete(demands, subscription1)
      assert Demands.size(demands) == 1
      assert Demands.get(demands, subscription1) == 0
      assert Demands.get(demands, subscription2) == 1000
      assert Demands.total(demands) == 1000
    end

    test "can be deleted for subscribers with no demands" do
      demands = Demands.new()
      subscription = Fakes.create_subscription()
      demands = Demands.add(demands, subscription, 100)
      demands = Demands.subtract(demands, subscription, 100)
      assert Demands.get(demands, subscription) == 0

      demands = Demands.delete(demands, subscription)
      assert Demands.get(demands, subscription) == 0
    end

    test "subscribers can be queried" do
      demands = Demands.new()
      subscription1 = Fakes.create_subscription()
      demands = Demands.add(demands, subscription1, 1)

      subscription2 = Fakes.create_subscription()
      demands = Demands.add(demands, subscription2, 1)

      subscribers = Demands.subscribers(demands)
      assert is_map(subscribers)
      assert map_size(subscribers) == 2
      assert Map.fetch!(subscribers, subscription1) == 1
      assert Map.fetch!(subscribers, subscription2) == 1
    end

    test "can be exported as a list of tuples" do
      demands = Demands.new()
      subscription1 = Fakes.create_subscription()
      subscription2 = Fakes.create_subscription()

      demands = Demands.add(demands, subscription1, 100)
      subscribers = Demands.subscribers(demands)
      assert is_map(subscribers)
      assert subscribers == %{subscription1 => 100}

      demands = Demands.add(demands, subscription2, 1)
      subscribers = Demands.subscribers(demands)
      assert is_map(subscribers)
      assert map_size(subscribers) == 2
      assert Map.fetch!(subscribers, subscription1) == 100
      assert Map.fetch!(subscribers, subscription2) == 1

      demands = Demands.subtract(demands, subscription2, 1)
      subscribers = Demands.subscribers(demands)
      assert is_map(subscribers)
      assert subscribers == %{subscription1 => 100}

      demands = Demands.add(demands, subscription1, 1)
      subscribers = Demands.subscribers(demands)
      assert is_map(subscribers)
      assert subscribers == %{subscription1 => 101}
    end
  end
end
