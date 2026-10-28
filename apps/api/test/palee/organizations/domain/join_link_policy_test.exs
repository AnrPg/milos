defmodule Palee.Organizations.Domain.JoinLinkPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Organizations.Domain.JoinLinkPolicy

  @off %{"member" => %{"enabled" => false}, "athlete" => %{"enabled" => false, "key" => nil}}

  test "defaults to both links off, the athlete link without a key" do
    assert JoinLinkPolicy.from_settings(%{}) == @off
    assert JoinLinkPolicy.from_settings(nil) == @off
  end

  test "carries the earlier single link over as the member link only" do
    # An earlier athlete link had no key, so it stays off until turned on again.
    assert JoinLinkPolicy.from_settings(%{
             "join_link" => %{"enabled" => true, "role" => "athlete"}
           }) == @off

    assert %{"member" => %{"enabled" => true}, "athlete" => %{"enabled" => false}} =
             JoinLinkPolicy.from_settings(%{
               "join_link" => %{"enabled" => true, "role" => "member"}
             })
  end

  test "never reads a staff role from stored settings" do
    stored = %{"join_link" => %{"enabled" => true, "role" => "admin"}, "x" => 1}
    assert JoinLinkPolicy.from_settings(stored) == @off

    stored = %{"join_link" => %{"admin" => %{"enabled" => true}}}
    assert JoinLinkPolicy.from_settings(stored) == @off
  end

  test "each link is switched on its own and both can be on" do
    assert {:ok, links} =
             JoinLinkPolicy.update(@off, %{"role" => "member", "enabled" => true}, "k1")

    assert links["member"] == %{"enabled" => true}
    assert links["athlete"] == %{"enabled" => false, "key" => nil}

    assert {:ok, links} = JoinLinkPolicy.update(links, %{role: "athlete", enabled: true}, "k2")
    assert links["member"]["enabled"]
    assert links["athlete"] == %{"enabled" => true, "key" => "k2"}
  end

  test "the athlete key survives off and on, and changes only when rotated" do
    {:ok, links} = JoinLinkPolicy.update(@off, %{"role" => "athlete", "enabled" => true}, "k1")
    {:ok, links} = JoinLinkPolicy.update(links, %{"role" => "athlete", "enabled" => false}, "k2")
    {:ok, links} = JoinLinkPolicy.update(links, %{"role" => "athlete", "enabled" => true}, "k3")
    assert links["athlete"]["key"] == "k1"

    {:ok, links} =
      JoinLinkPolicy.update(links, %{"role" => "athlete", "rotate_key" => true}, "k4")

    assert links["athlete"] == %{"enabled" => true, "key" => "k4"}
  end

  test "rejects staff roles, a missing role, non-boolean values and rotating the member link" do
    for params <- [
          %{"role" => "owner", "enabled" => true},
          %{"enabled" => true},
          %{"role" => "member", "enabled" => "yes"},
          %{"role" => "athlete", "rotate_key" => "yes"},
          %{"role" => "member", "rotate_key" => true}
        ] do
      assert {:error, :invalid_join_link} = JoinLinkPolicy.update(@off, params, "k")
    end
  end

  test "the member link needs no key, the athlete link needs its own key" do
    links = %{"member" => %{"enabled" => true}, "athlete" => %{"enabled" => true, "key" => "abc"}}

    assert JoinLinkPolicy.joinable?(links, "member", nil, :active)
    assert JoinLinkPolicy.joinable?(links, "athlete", "abc", :active)
    refute JoinLinkPolicy.joinable?(links, "athlete", nil, :active)
    refute JoinLinkPolicy.joinable?(links, "athlete", "abd", :active)
    refute JoinLinkPolicy.joinable?(links, "athlete", "abcd", :active)
    refute JoinLinkPolicy.joinable?(links, "admin", nil, :active)
    refute JoinLinkPolicy.joinable?(links, "member", nil, :suspended)

    refute JoinLinkPolicy.joinable?(
             put_in(links, ["member", "enabled"], false),
             "member",
             nil,
             :active
           )
  end

  test "new keys are URL-safe and differ" do
    key = JoinLinkPolicy.new_key()
    assert key =~ ~r/\A[A-Za-z0-9_-]{12}\z/
    refute key == JoinLinkPolicy.new_key()
  end

  test "joining never reactivates a suspended membership" do
    assert JoinLinkPolicy.join_decision(nil) == :create
    assert JoinLinkPolicy.join_decision(%{status: :active}) == :already_member

    assert JoinLinkPolicy.join_decision(%{status: :suspended}) ==
             {:error, :membership_unavailable}
  end
end
