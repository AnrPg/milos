defmodule PaleeWeb.TrainingGoalControllerTest do
  @moduledoc """
  ADR-226: the weekly workout goal is the person's own. They set it; their
  coach or an owner/admin with full coaching scope may set it for them (and
  the person is told); nobody else may read or change it. Runs under real
  RLS (ConnCase), so `palee_training_goal_reachable` is exercised too.
  """

  use PaleeWeb.ConnCase, async: false

  alias Palee.{Notifications, Organizations, Repo}

  import Palee.TestFixtures

  setup do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    owner = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(owner, :owner)
    coach = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(coach, :coach)

    %{
      owner: owner,
      coach: coach,
      base: "/api/org/#{Organizations.legacy_organization_slug()}"
    }
  end

  defp person(role) do
    user = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
    user
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp as(conn, user), do: conn |> recycle() |> put_bearer_token(user)

  test "a member reads the default and sets their own goal", %{conn: conn} do
    member = person(:member)

    assert %{
             "goal" => %{
               "weekly_workout_target" => 2,
               "is_default" => true,
               "set_by_role" => nil,
               "min" => 1,
               "max" => 14
             }
           } = conn |> as(member) |> get("/api/gamification/goal") |> json_response(200)

    assert %{"goal" => %{"weekly_workout_target" => 4, "is_default" => false} = goal} =
             conn
             |> as(member)
             |> send_json(:put, "/api/gamification/goal", %{weekly_workout_target: 4})
             |> json_response(200)

    assert goal["set_by_role"] == "self"

    assert %{"goal" => %{"weekly_workout_target" => 4}} =
             conn |> as(member) |> get("/api/gamification/goal") |> json_response(200)

    for bad <- [0, 15] do
      assert conn
             |> as(member)
             |> send_json(:put, "/api/gamification/goal", %{weekly_workout_target: bad})
             |> json_response(422)
    end

    # Setting their own goal never notifies them.
    refute Enum.any?(
             Notifications.list_for_user(member.id),
             &(&1.type == "training_goal_updated")
           )
  end

  test "a coach sets their client's goal, the client is told and can change it back", %{
    conn: conn,
    coach: coach,
    base: base
  } do
    client = person(:athlete)
    other = person(:athlete)

    conn
    |> as(coach)
    |> send_json(:post, "#{base}/staff/coaching-relationships", %{client_user_id: client.id})
    |> json_response(201)

    path = "#{base}/staff/clients/#{client.id}/training-goal"

    assert %{"goal" => %{"is_default" => true}} =
             conn |> as(coach) |> get(path) |> json_response(200)

    assert %{"goal" => %{"weekly_workout_target" => 5, "set_by_role" => "coach"} = goal} =
             conn
             |> as(coach)
             |> send_json(:put, path, %{weekly_workout_target: 5})
             |> json_response(200)

    assert goal["set_by_nickname"] == coach.nickname

    assert [%{payload: payload}] =
             client.id
             |> Notifications.list_for_user()
             |> Enum.filter(&(&1.type == "training_goal_updated"))

    assert payload["target"] == 5
    assert payload["set_by_nickname"] == coach.nickname

    # The member sees who set it and keeps the last word.
    assert %{"goal" => %{"weekly_workout_target" => 5, "set_by_role" => "coach"}} =
             conn |> as(client) |> get("/api/gamification/goal") |> json_response(200)

    assert %{"goal" => %{"weekly_workout_target" => 3, "set_by_role" => "self"}} =
             conn
             |> as(client)
             |> send_json(:put, "/api/gamification/goal", %{weekly_workout_target: 3})
             |> json_response(200)

    # A coach with own-client scope cannot reach someone they do not coach.
    assert conn
           |> as(coach)
           |> send_json(:put, "#{base}/staff/clients/#{other.id}/training-goal", %{
             weekly_workout_target: 3
           })
           |> json_response(403)

    assert conn
           |> as(coach)
           |> get("#{base}/staff/clients/#{other.id}/training-goal")
           |> json_response(403)
  end

  test "a head coach (full coaching scope) sets the goal of a client they do not coach", %{
    conn: conn,
    base: base
  } do
    head = user_fixture()
    {:ok, membership} = Organizations.ensure_legacy_membership_for_migration(head, :coach)
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()

    {:ok, _} =
      Palee.Organizations.OrganizationStore.update_membership_settings(
        organization.id,
        membership.id,
        %{coach_scope: :all}
      )

    client = person(:member)
    path = "#{base}/staff/clients/#{client.id}/training-goal"

    assert %{"goal" => %{"is_default" => true}} =
             conn |> as(head) |> get(path) |> json_response(200)

    assert %{"goal" => %{"weekly_workout_target" => 4, "set_by_role" => "staff"}} =
             conn
             |> as(head)
             |> send_json(:put, path, %{weekly_workout_target: 4})
             |> json_response(200)

    assert %{"goal" => %{"weekly_workout_target" => 4}} =
             conn |> as(client) |> get("/api/gamification/goal") |> json_response(200)
  end

  test "an owner sets any client's goal; front desk, members and other gyms cannot", %{
    conn: conn,
    owner: owner,
    base: base
  } do
    client = person(:member)
    desk = person(:front_desk)
    path = "#{base}/staff/clients/#{client.id}/training-goal"

    assert %{"goal" => %{"weekly_workout_target" => 3, "set_by_role" => "staff"}} =
             conn
             |> as(owner)
             |> send_json(:put, path, %{weekly_workout_target: 3})
             |> json_response(200)

    assert Enum.any?(
             Notifications.list_for_user(client.id),
             &(&1.type == "training_goal_updated")
           )

    assert conn |> as(desk) |> get(path) |> json_response(403)

    assert conn
           |> as(desk)
           |> send_json(:put, path, %{weekly_workout_target: 6})
           |> json_response(403)

    # A member never reaches another person's goal.
    assert conn |> as(person(:member)) |> get(path) |> json_response(403)

    # The owner of another gym is refused for a person who is not theirs.
    other_owner = admin_fixture()

    {:ok, other_gym} =
      Organizations.create_organization(%{
        name: "Other Gym #{System.unique_integer([:positive])}"
      })

    {:ok, _} =
      Organizations.add_membership(%{
        organization_id: other_gym.id,
        user_id: other_owner.id,
        role: :owner,
        status: :active
      })

    assert conn
           |> as(other_owner)
           |> send_json(
             :put,
             "/api/org/#{other_gym.slug}/staff/clients/#{client.id}/training-goal",
             %{
               weekly_workout_target: 6
             }
           )
           |> json_response(404)

    assert %{"goal" => %{"weekly_workout_target" => 3}} =
             conn |> as(client) |> get("/api/gamification/goal") |> json_response(200)
  end
end
