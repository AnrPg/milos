defmodule PaleeWeb.GroupWodVariationsControllerTest do
  @moduledoc """
  ADR-201: one workout programmed for several people at once. Each person is
  programmed exactly as the one-person endpoint would program them alone; the
  answer lists one result per person and a failure never undoes the others.
  """
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Finance, Organizations, Scheduling}
  alias Palee.Application.ProgramWorkoutForUsers

  @programming_plan %{
    "entitlement_version" => 1,
    "channels" => ["in_person", "personal_programming"],
    "capabilities" => [
      "book_classes",
      "execute_class_workouts",
      "execute_assigned_workouts",
      "receive_coaching_touchpoints"
    ],
    "allowances" => %{
      "coaching_touchpoints" => %{"limit" => "unlimited", "period" => "calendar_month"}
    }
  }

  @class_only_plan %{
    "entitlement_version" => 1,
    "channels" => ["in_person"],
    "capabilities" => ["book_classes", "execute_class_workouts"],
    "allowances" => %{}
  }

  defp tenant(name) do
    admin = admin_fixture(%{nickname: "#{name}_admin_#{System.unique_integer([:positive])}"})
    {:ok, organization} = Organizations.create_organization(%{name: "#{name} Gym"})
    add_membership(organization, admin, :owner)
    {:ok, context} = Organizations.resolve_tenant_context(admin, organization.slug)
    %{admin: admin, organization: organization, context: context}
  end

  defp add_membership(organization, user, role) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    user
  end

  defp member(gym, nickname, plan) do
    %{nickname: "#{nickname}_#{System.unique_integer([:positive])}", role: :member}
    |> user_fixture()
    |> then(&add_membership(gym.organization, &1, :member))
    |> then(&give_package(gym, &1, plan))
  end

  defp give_package(%{context: context}, user, plan) do
    {:ok, package} =
      Finance.create_package(context, %{
        code: "adr201-#{System.unique_integer([:positive])}",
        name: "ADR-201 package",
        family: "hybrid",
        billing_period: "monthly",
        params: plan
      })

    {:ok, membership} =
      Finance.upsert_membership(context, user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, _subscription} =
      Finance.assign_package(context, membership.id, package.id, %{starts_on: Date.utc_today()})

    user
  end

  defp booked_class(%{context: context}, workout, members) do
    class_type = class_type_fixture(%{tenant_context: context})

    slot =
      slot_fixture(workout, %{
        tenant_context: context,
        class_type_id: class_type.id,
        auto_approve: true,
        scheduled_at: DateTime.utc_now() |> DateTime.add(2 * 3600) |> DateTime.truncate(:second)
      })

    Enum.each(members, fn member ->
      {:ok, _booking} = Scheduling.submit_auto_approved_booking(context, member.id, slot.id)
    end)

    slot
  end

  defp program_many(conn, gym, body) do
    conn
    |> recycle()
    |> put_bearer_token(gym.admin)
    |> post("/api/org/#{gym.organization.slug}/admin/users/programming", Jason.encode!(body))
  end

  defp by_user(results), do: Map.new(results, &{&1["user_id"], &1})

  test "a class variant for several attendees gives each their own copy in their own folder", %{
    conn: conn
  } do
    gym = tenant("grp_variant")
    anna = member(gym, "grp_anna", @programming_plan)
    babis = member(gym, "grp_babis", @programming_plan)
    class_wod = workout_fixture(gym.admin, %{title: "Class WOD", tenant_context: gym.context})
    slot = booked_class(gym, class_wod, [anna, babis])
    day = slot.scheduled_at |> DateTime.to_date() |> Date.to_iso8601()

    results =
      conn
      |> program_many(gym, %{
        user_ids: [anna.id, babis.id],
        scheduled_for: day,
        slot_id: slot.id,
        copy_source: true,
        mode: "class_variant"
      })
      |> json_response(200)
      |> Map.fetch!("results")

    assert Enum.map(results, & &1["user_id"]) == [anna.id, babis.id]
    assert Enum.all?(results, &(&1["status"] == "ok" and &1["mode"] == "class_variant"))

    [first, second] = results
    assert first["workout"]["id"] != second["workout"]["id"]
    assert first["workout"]["folder_id"] != second["workout"]["folder_id"]
    assert first["workout"]["source_workout_id"] == class_wod.id
    assert first["association"]["source_slot_id"] == slot.id
    assert first["association"]["assignment_kind"] == "class_variant"

    # The class keeps its own workout for everyone.
    assert Scheduling.get_slot(gym.context, slot.id).master_workout_id == class_wod.id

    variant_owners =
      gym.context
      |> Palee.Workouts.list_class_variants([slot.id], nil)
      |> Enum.map(& &1.assignee_id)
      |> Enum.sort()

    assert variant_owners == Enum.sort([anna.id, babis.id])
  end

  test "one person failing does not undo the others; each failure names its code", %{conn: conn} do
    gym = tenant("grp_partial")
    entitled = member(gym, "grp_entitled", @programming_plan)
    plain = member(gym, "grp_plain", @class_only_plan)
    not_booked = member(gym, "grp_not_booked", @programming_plan)
    class_wod = workout_fixture(gym.admin, %{title: "Partial WOD", tenant_context: gym.context})
    slot = booked_class(gym, class_wod, [entitled, plain])
    day = slot.scheduled_at |> DateTime.to_date() |> Date.to_iso8601()

    results =
      conn
      |> program_many(gym, %{
        user_ids: [plain.id, entitled.id, not_booked.id],
        scheduled_for: day,
        slot_id: slot.id,
        copy_source: true,
        mode: "class_variant"
      })
      |> json_response(200)
      |> Map.fetch!("results")
      |> by_user()

    assert results[entitled.id]["status"] == "ok"

    assert %{"status" => "error", "code" => "member_programming_not_entitled", "params" => params} =
             results[plain.id]

    assert params["nickname"] == plain.nickname

    assert %{"status" => "error", "code" => "slot_not_booked_by_member"} =
             results[not_booked.id]

    assert [%{assignee_id: user_id}] =
             Palee.Workouts.list_class_variants(gym.context, [slot.id], nil)

    assert user_id == entitled.id
  end

  test "duplicate ids are programmed once; an empty or oversized list is refused", %{conn: conn} do
    gym = tenant("grp_dedupe")
    anna = member(gym, "grp_dedupe_anna", @programming_plan)
    wod = workout_fixture(gym.admin, %{title: "Personal WOD", tenant_context: gym.context})
    day = Date.utc_today() |> Date.add(1) |> Date.to_iso8601()

    body = %{
      master_workout_id: wod.id,
      scheduled_for: day,
      copy_source: true,
      mode: "personal"
    }

    assert [%{"user_id" => user_id, "status" => "ok", "mode" => "personal"}] =
             conn
             |> program_many(gym, Map.put(body, :user_ids, [anna.id, anna.id]))
             |> json_response(200)
             |> Map.fetch!("results")

    assert user_id == anna.id

    assert conn
           |> program_many(gym, Map.put(body, :user_ids, []))
           |> json_response(422)

    too_many = Enum.map(1..51, fn _ -> Ecto.UUID.generate() end)

    assert conn
           |> program_many(gym, Map.put(body, :user_ids, too_many))
           |> json_response(422)
  end

  test "the use case dedupes before capping and refuses more than 50 people" do
    gym = tenant("grp_cap")
    params = %{"scheduled_for" => Date.to_iso8601(Date.utc_today()), "mode" => "personal"}
    many = Enum.map(1..51, fn _ -> Ecto.UUID.generate() end)

    assert {:error, :too_many_users} =
             ProgramWorkoutForUsers.call(gym.context, gym.admin, many, params)

    assert {:error, :invalid_user_ids} =
             ProgramWorkoutForUsers.call(gym.context, gym.admin, [], params)

    unknown = Ecto.UUID.generate()
    repeated = List.duplicate(unknown, 60)

    assert {:ok, %{results: [%{user_id: ^unknown, status: "error", code: "not_found"}]}} =
             ProgramWorkoutForUsers.call(gym.context, gym.admin, repeated, params)
  end

  test "a coach with scope own programs only their own clients", %{conn: conn} do
    gym = tenant("grp_scope")
    client = member(gym, "grp_client", @programming_plan)
    stranger = member(gym, "grp_stranger", @programming_plan)
    wod = workout_fixture(gym.admin, %{title: "Scoped WOD", tenant_context: gym.context})

    coach =
      %{nickname: "grp_coach_#{System.unique_integer([:positive])}", role: :member}
      |> user_fixture()
      |> then(&add_membership(gym.organization, &1, :coach))

    {:ok, _relationship} =
      bypass_rls(fn ->
        Palee.Coaching.start_relationship(%{organization_id: gym.organization.id}, %{
          coach_user_id: coach.id,
          client_user_id: client.id,
          origin: "assigned"
        })
      end)

    results =
      conn
      |> program_many(%{gym | admin: coach}, %{
        user_ids: [client.id, stranger.id],
        master_workout_id: wod.id,
        scheduled_for: Date.utc_today() |> Date.add(1) |> Date.to_iso8601(),
        copy_source: true,
        mode: "personal"
      })
      |> json_response(200)
      |> Map.fetch!("results")
      |> by_user()

    assert results[client.id]["status"] == "ok"

    assert results[stranger.id] == %{
             "user_id" => stranger.id,
             "status" => "error",
             "code" => "not_your_client"
           }
  end
end
