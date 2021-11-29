defmodule Dispenser.SubscriptionManagerTest do
  @moduledoc false
  use ExUnit.Case

  alias Dispenser.{DummyConsumer, SubscriptionManager}

  describe "subscription manager" do
    test "can be created" do
      manager = SubscriptionManager.new()
      assert SubscriptionManager.size(manager) == 0
    end

    test "subscriptions can be added" do
      manager = SubscriptionManager.new()
      {:ok, subscription1} = DummyConsumer.start_link([])
      manager = SubscriptionManager.monitor(manager, subscription1)
      assert SubscriptionManager.size(manager) == 1

      {:ok, subscription2} = DummyConsumer.start_link([])
      manager = SubscriptionManager.monitor(manager, subscription2)
      assert SubscriptionManager.size(manager) == 2
    end

    test "duplicate subscriptions are deduplicated" do
      manager = SubscriptionManager.new()
      {:ok, subscription} = DummyConsumer.start_link([])
      manager = SubscriptionManager.monitor(manager, subscription)
      assert SubscriptionManager.size(manager) == 1

      manager = SubscriptionManager.monitor(manager, subscription)
      assert SubscriptionManager.size(manager) == 1
    end

    test "subscriptions can be removed" do
      manager = SubscriptionManager.new()
      {:ok, subscription1} = DummyConsumer.start_link([])
      manager = SubscriptionManager.monitor(manager, subscription1)
      assert SubscriptionManager.size(manager) == 1

      {:ok, subscription2} = DummyConsumer.start_link([])
      manager = SubscriptionManager.monitor(manager, subscription2)
      assert SubscriptionManager.size(manager) == 2

      {:ok, manager} = SubscriptionManager.demonitor(manager, subscription1)
      assert SubscriptionManager.size(manager) == 1

      {:ok, manager} = SubscriptionManager.demonitor(manager, subscription2)
      assert SubscriptionManager.size(manager) == 0
    end

    test "subscriptions can't be removed if they don't exist" do
      manager = SubscriptionManager.new()
      {:ok, subscription} = DummyConsumer.start_link([])
      {:error, :not_subscribed} = SubscriptionManager.demonitor(manager, subscription)
      assert SubscriptionManager.size(manager) == 0
    end

    test "subscriptions can't be handled by down if they don't exist" do
      manager = SubscriptionManager.new()

      {:ok, subscription} = DummyConsumer.start_link([])
      Process.unlink(subscription)
      ref = Process.monitor(subscription)
      Process.exit(subscription, :kill)
      assert_receive {:DOWN, ^ref, :process, ^subscription, :killed}, 1000

      {:error, :not_subscribed} = SubscriptionManager.down(manager, subscription, ref)
      assert SubscriptionManager.size(manager) == 0
    end

    test "subscriptions can be removed when they go down" do
      manager = SubscriptionManager.new()
      {:ok, subscription} = DummyConsumer.start_link([])
      Process.unlink(subscription)

      manager = SubscriptionManager.monitor(manager, subscription)
      assert SubscriptionManager.size(manager) == 1

      Process.exit(subscription, :kill)
      assert_receive {:DOWN, ref, :process, ^subscription, :killed}, 1000

      {:ok, manager} = SubscriptionManager.down(manager, subscription, ref)

      assert SubscriptionManager.size(manager) == 0
    end

    test "subscriptions can only be removed when they go down if the ref is from SubscriptionManager.monitor" do
      manager = SubscriptionManager.new()
      {:ok, subscription} = DummyConsumer.start_link([])
      Process.unlink(subscription)
      wrong_ref = Process.monitor(subscription)

      manager = SubscriptionManager.monitor(manager, subscription)
      assert SubscriptionManager.size(manager) == 1

      Process.exit(subscription, :kill)
      assert_receive {:DOWN, ref1, :process, ^subscription, :killed}, 1000
      assert_receive {:DOWN, ref2, :process, ^subscription, :killed}, 1000

      correct_ref =
        if ref1 == wrong_ref do
          ref2
        else
          ref1
        end

      {:error, :wrong_ref} = SubscriptionManager.down(manager, subscription, wrong_ref)

      assert SubscriptionManager.size(manager) == 1

      {:ok, manager} = SubscriptionManager.down(manager, subscription, correct_ref)

      assert SubscriptionManager.size(manager) == 0
    end
  end
end
