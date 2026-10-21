defmodule MilosTrainingWeb.BookingSharingTest do
  @moduledoc """
  ADR-142 decision 12 (board 5 Q6): followers see the classes a person books
  only after that person turns sharing on; the «Φίλοι» chip reads
  `friends_going` on each class of the member schedule.
  """

  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Organizations, Scheduling}

  import MilosTraining.TestFixtures

  defp legacy_tenant_context(actor, role \\ nil) do
    {:ok, _membership} = Organizations.ensure_legacy_membership_for_migration(actor, role)

    {:ok, context} =
      Organizations.resolve_tenant_context(actor, Organizations.legacy_organization_slug())

    context
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp as(user), do: build_conn() |> put_bearer_token(user)

  defp friends_going(user, slot) do
    as(user)
    |> get("/api/org/#{Organizations.legacy_organization_slug()}/schedule")
    |> json_response(200)
    |> Map.fetch!("slots")
    |> Enum.find(&(&1["id"] == slot.id))
    |> Map.fetch!("friends_going")
    |> Enum.map(& &1["id"])
  end

  defp follow!(follower, target, accept?) do
    assert %{"status" => "requested"} =
             as(follower)
             |> send_json("POST", "/api/me/follows", %{target_type: "user", target_id: target.id})
             |> json_response(200)

    if accept? do
      %{"entries" => [%{"follow_id" => follow_id}]} =
        as(target) |> get("/api/me/follow-requests") |> json_response(200)

      as(target) |> post("/api/me/follow-requests/#{follow_id}/accept") |> response(204)
    end
  end

  setup do
    admin = admin_fixture()
    legacy_tenant_context(admin, :owner)
    [ana, ben, cat] = for _ <- 1..3, do: user_fixture()
    ana_context = legacy_tenant_context(ana)
    legacy_tenant_context(ben)
    legacy_tenant_context(cat)
    slot = slot_fixture(workout_fixture(admin, %{title: "Friends WOD"}), %{auto_approve: true})
    {:ok, _booking} = Scheduling.submit_auto_approved_booking(ana_context, ana.id, slot.id)
    %{ana: ana, ben: ben, cat: cat, slot: slot}
  end

  test "an accepted follower sees the booking only once the person shares", ctx do
    %{ana: ana, ben: ben, cat: cat, slot: slot} = ctx
    follow!(ben, ana, true)
    follow!(cat, ana, false)

    assert %{"booking_sharing" => %{"enabled" => false, "offered" => false}} =
             as(ana) |> get("/api/me/social") |> json_response(200)

    assert friends_going(ben, slot) == []

    assert %{"enabled" => true, "offered" => true} =
             as(ana)
             |> send_json("PUT", "/api/me/social/booking-sharing", %{enabled: true})
             |> json_response(200)

    assert friends_going(ben, slot) == [ana.id]
    # A request that was never accepted shows nothing.
    assert friends_going(cat, slot) == []
    # Your own booking is not a friend's.
    assert friends_going(ana, slot) == []

    assert %{"enabled" => false, "offered" => true} =
             as(ana)
             |> send_json("PUT", "/api/me/social/booking-sharing", %{enabled: false})
             |> json_response(200)

    assert friends_going(ben, slot) == []
  end

  test "the setting is the owner's alone", ctx do
    assert %{"errors" => _} =
             as(ctx.ana)
             |> send_json("PUT", "/api/me/social/booking-sharing", %{enabled: "yes"})
             |> json_response(422)
  end
end
