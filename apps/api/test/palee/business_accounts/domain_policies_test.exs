defmodule Palee.BusinessAccounts.DomainPoliciesTest do
  @moduledoc "ADR-184: activation links, requests and the demo seeder plan."
  use ExUnit.Case, async: true

  alias Palee.Application.DemoSeeders
  alias Palee.BusinessAccounts.Domain.{ActivationLinkPolicy, BusinessRequestPolicy}

  describe "activation links" do
    test "tokens decode to their digest; anything else is an invalid link" do
      token = ActivationLinkPolicy.generate_token()
      assert byte_size(token) >= 40
      assert {:ok, digest} = ActivationLinkPolicy.decode(token)
      assert digest == ActivationLinkPolicy.digest(token)
      assert {:error, :invalid_activation_link} == ActivationLinkPolicy.decode(nil)
      assert "/activate-business#token=" <> ^token = ActivationLinkPolicy.path(token)
    end

    test "a vendor picks owner or admin and a lifetime of one hour to 30 days" do
      assert {:ok, %{role: "owner", lifetime_seconds: 604_800}} =
               ActivationLinkPolicy.normalize_issue(%{})

      assert {:ok, %{role: "admin", lifetime_seconds: 3600}} =
               ActivationLinkPolicy.normalize_issue(%{
                 "role" => "admin",
                 "lifetime_seconds" => 3600
               })

      assert {:error, :invalid_activation_role} =
               ActivationLinkPolicy.normalize_issue(%{role: "member"})

      assert {:error, :invalid_activation_lifetime} =
               ActivationLinkPolicy.normalize_issue(%{lifetime_seconds: 60})

      assert {:error, :invalid_activation_lifetime} =
               ActivationLinkPolicy.normalize_issue(%{lifetime_seconds: 31 * 86_400})
    end

    test "states" do
      now = ~U[2026-12-06 10:00:00Z]
      later = DateTime.add(now, 3600)
      assert :live == ActivationLinkPolicy.state(%{expires_at: later}, now)
      assert :expired == ActivationLinkPolicy.state(%{expires_at: now}, now)
      assert :redeemed == ActivationLinkPolicy.state(%{redeemed_at: now, expires_at: later}, now)

      assert :revoked ==
               ActivationLinkPolicy.state(
                 %{redeemed_at: nil, revoked_at: now, expires_at: later},
                 now
               )
    end

    test "the practice is the coach: activation keeps the coach role" do
      assert [:owner, :coach] ==
               ActivationLinkPolicy.roles_after([:owner, :coach], "owner", "coach")

      assert [:member, :admin] == ActivationLinkPolicy.roles_after([:member], "admin", "gym")
      assert [:admin, :coach] == ActivationLinkPolicy.roles_after(nil, "admin", "coach")
    end
  end

  describe "requests" do
    test "sign-up lasts 30 minutes after registering" do
      now = ~U[2026-12-06 10:00:00Z]
      assert BusinessRequestPolicy.signing_up?(DateTime.add(now, -60), now)
      assert BusinessRequestPolicy.signing_up?(~N[2026-12-06 09:45:00], now)
      refute BusinessRequestPolicy.signing_up?(DateTime.add(now, -31 * 60), now)
      refute BusinessRequestPolicy.signing_up?(nil, now)
    end

    test "details are trimmed and checked" do
      assert {:ok, %{business_kind: "gym", business_name: "Box", city: nil}} =
               BusinessRequestPolicy.normalize_details(%{
                 "business_kind" => "gym",
                 "business_name" => "  Box ",
                 "city" => " "
               })

      assert {:error, :invalid_business_kind} =
               BusinessRequestPolicy.normalize_details(%{
                 business_kind: "organiser",
                 business_name: "Runs"
               })

      assert {:error, :invalid_name} =
               BusinessRequestPolicy.normalize_details(%{
                 business_kind: "coach",
                 business_name: "N"
               })

      assert {:error, :invalid_business_request} =
               BusinessRequestPolicy.normalize_details(%{
                 business_kind: "coach",
                 business_name: "Nikos",
                 message: String.duplicate("a", 1001)
               })
    end

    test "decisions" do
      assert {:ok, %{decision: "approve", note: nil}} =
               BusinessRequestPolicy.normalize_decision(%{decision: "approve"})

      assert {:error, :invalid_decision} =
               BusinessRequestPolicy.normalize_decision(%{decision: "maybe"})

      assert BusinessRequestPolicy.open?(%{status: "pending"})
      refute BusinessRequestPolicy.open?(%{status: "approved"})
    end
  end

  describe "demo seeders" do
    test "a section brings the sections it needs first, once" do
      assert {:ok, plan} = DemoSeeders.plan("schedule", [])
      assert ~w(members workouts schedule) == Enum.map(plan, & &1.section())

      assert {:ok, plan} = DemoSeeders.plan("schedule", ["members"])
      assert ~w(workouts schedule) == Enum.map(plan, & &1.section())

      assert {:ok, plan} = DemoSeeders.plan("all", [])
      sections = Enum.map(plan, & &1.section())
      assert Enum.sort(sections) == Enum.sort(DemoSeeders.sections())
      assert hd(sections) == "members"

      assert {:ok, []} = DemoSeeders.plan("finance", ["members", "finance"])
      assert {:error, :unknown_demo_section} = DemoSeeders.plan("reports", [])
    end

    test "every seeder writes only tables the activation wipe removes" do
      deletable = Palee.BusinessAccounts.demo_deletable_sources()

      for seeder <- DemoSeeders.all(), source <- seeder.sources(), source != "users" do
        assert source in deletable, "#{seeder.section()} writes #{source}"
      end
    end
  end
end
