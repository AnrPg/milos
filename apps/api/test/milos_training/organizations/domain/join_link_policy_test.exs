defmodule MilosTraining.Organizations.Domain.JoinLinkPolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Organizations.Domain.JoinLinkPolicy

  test "defaults to a disabled member link" do
    assert JoinLinkPolicy.from_settings(%{}) == %{"enabled" => false, "role" => "member"}
    assert JoinLinkPolicy.from_settings(nil) == %{"enabled" => false, "role" => "member"}
  end

  test "never reads a staff role from stored settings" do
    stored = %{"join_link" => %{"enabled" => true, "role" => "admin"}}
    assert JoinLinkPolicy.from_settings(stored) == %{"enabled" => true, "role" => "member"}
  end

  test "updates merge over the current link and only allow client roles" do
    current = %{"enabled" => false, "role" => "member"}

    assert {:ok, %{"enabled" => true, "role" => "member"}} =
             JoinLinkPolicy.update(current, %{"enabled" => true})

    assert {:ok, %{"enabled" => false, "role" => "athlete"}} =
             JoinLinkPolicy.update(current, %{role: "athlete"})

    assert {:error, :invalid_join_link} = JoinLinkPolicy.update(current, %{"role" => "owner"})
    assert {:error, :invalid_join_link} = JoinLinkPolicy.update(current, %{"enabled" => "yes"})
  end

  test "only active organizations with an enabled link are joinable" do
    assert JoinLinkPolicy.joinable?(%{"enabled" => true}, :active)
    refute JoinLinkPolicy.joinable?(%{"enabled" => true}, :suspended)
    refute JoinLinkPolicy.joinable?(%{"enabled" => false}, :active)
  end

  test "joining never reactivates a suspended membership" do
    assert JoinLinkPolicy.join_decision(nil) == :create
    assert JoinLinkPolicy.join_decision(%{status: :active}) == :already_member

    assert JoinLinkPolicy.join_decision(%{status: :suspended}) ==
             {:error, :membership_unavailable}
  end
end
