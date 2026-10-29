defmodule PaleeWeb.PersonalizedMemberProgrammingControllerTest do
  @moduledoc """
  ADR-125 (TD-037): personalized member programming end to end, through the
  RLS-enforcing endpoint - entitlement gating, member vs athlete, class-variant
  visibility and tenant isolation.
  """
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Finance, Organizations, Repo, Scheduling, Workouts}
  alias Palee.Workouts.MasterWorkout

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

  defp customer(%{organization: organization}, role, nickname) do
    account_role = if role == :athlete, do: :athlete, else: :member

    %{nickname: "#{nickname}_#{System.unique_integer([:positive])}", role: account_role}
    |> user_fixture()
    |> then(&add_membership(organization, &1, role))
  end

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

  defp give_package(%{context: context}, user, plan, user_type \\ "member") do
    {:ok, package} =
      Finance.create_package(context, %{
        code: "td037-#{System.unique_integer([:positive])}",
        name: "TD-037 package",
        family: "hybrid",
        billing_period: "monthly",
        params: plan
      })

    {:ok, membership} =
      Finance.upsert_membership(context, user.id, %{
        user_type_snapshot: user_type,
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, _subscription} =
      Finance.assign_package(context, membership.id, package.id, %{starts_on: Date.utc_today()})

    user
  end

  defp workout(%{admin: admin, context: context}, title),
    do: workout_fixture(admin, %{title: title, tenant_context: context})

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

  defp api(conn, user), do: conn |> recycle() |> put_bearer_token(user)

  defp slug(%{organization: organization}), do: organization.slug

  defp assign_workout(conn, tenant, params) do
    conn
    |> api(tenant.admin)
    |> post("/api/org/#{slug(tenant)}/admin/assigned-workouts", Jason.encode!(params))
  end

  defp my_workouts(conn, tenant, user) do
    conn
    |> api(user)
    |> get("/api/org/#{slug(tenant)}/my-workouts?start_date=#{Date.utc_today()}")
    |> json_response(200)
    |> Map.fetch!("assignments")
  end

  defp schedule_slot(conn, tenant, user, slot_id) do
    conn
    |> api(user)
    |> get("/api/org/#{slug(tenant)}/schedule?start_date=#{Date.utc_today()}")
    |> json_response(200)
    |> Map.fetch!("slots")
    |> Enum.find(&(&1["id"] == slot_id))
  end

  defp start_assigned(conn, user, workout_id, assignment_id) do
    conn
    |> api(user)
    |> post(
      "/api/executions",
      Jason.encode!(%{
        master_workout_id: workout_id,
        source: "assigned",
        source_reference_id: assignment_id
      })
    )
  end

  defp workout_count(context) do
    bypass_rls(fn ->
      import Ecto.Query

      MasterWorkout
      |> where([w], w.organization_id == ^context.organization_id)
      |> Repo.aggregate(:count)
    end)
  end

  describe "personal WODs for members" do
    test "an entitled member is assigned alongside an athlete, sees it and starts it", %{
      conn: conn
    } do
      gym = tenant("pm_personal")

      member =
        gym |> customer(:member, "pm_member") |> then(&give_package(gym, &1, @programming_plan))

      athlete =
        gym
        |> customer(:athlete, "pm_athlete")
        |> then(&give_package(gym, &1, @programming_plan, "athlete"))

      wod = workout(gym, "Personal engine")
      today = Date.utc_today() |> Date.to_iso8601()

      created =
        conn
        |> assign_workout(gym, %{
          master_workout_id: wod.id,
          athlete_ids: [member.id, athlete.id],
          scheduled_for: today
        })
        |> json_response(201)
        |> Map.fetch!("assignment")

      assert created["assignment_kind"] == "personal"
      assert created["source_slot_id"] == nil

      assert [%{"id" => assignment_id, "assignment_kind" => "personal"} = mine] =
               my_workouts(conn, gym, member)

      assert assignment_id == created["id"]
      # Members never see who else received the same assignment.
      refute Map.has_key?(mine, "athlete_ids")

      # The member is notified exactly like an athlete.
      assert Enum.any?(
               Palee.Notifications.list_for_user(member.id),
               &(to_string(&1.type) == "workout_assigned")
             )

      execution =
        conn
        |> start_assigned(member, wod.id, assignment_id)
        |> json_response(201)
        |> Map.fetch!("execution")

      assert execution["source"] == "assigned"
      assert execution["source_reference_id"] == assignment_id

      # Completion counts in gamification like any execution.
      conn
      |> api(member)
      |> patch(
        "/api/executions/#{execution["id"]}/complete",
        Jason.encode!(%{section_scores: []})
      )
      |> json_response(200)

      assert %{total_workouts: 1} = Palee.Gamification.get_user_stats(member.id)

      assert [%{"execution_status" => "completed"}] = my_workouts(conn, gym, member)

      # Staff see the member on the board with their role.
      board =
        conn
        |> api(gym.admin)
        |> get("/api/org/#{slug(gym)}/my-workouts?start_date=#{today}")
        |> json_response(200)
        |> Map.fetch!("assignments")

      assert [%{"athletes" => athletes}] = board
      assert Enum.sort(Enum.map(athletes, & &1["role"])) == ["athlete", "member"]
    end

    test "a person without online programming or personal training is refused, even in observe rollout",
         %{conn: conn} do
      gym = tenant("pm_denied")

      plain =
        gym |> customer(:member, "pm_plain") |> then(&give_package(gym, &1, @class_only_plan))

      unmanaged = customer(gym, :member, "pm_unmanaged")
      athlete = customer(gym, :athlete, "pm_unmanaged_athlete")
      wod = workout(gym, "Gated WOD")
      today = Date.utc_today() |> Date.to_iso8601()

      denied =
        conn
        |> assign_workout(gym, %{
          master_workout_id: wod.id,
          athlete_ids: [plain.id],
          scheduled_for: today
        })
        |> json_response(403)

      assert denied["code"] == "programming_not_in_package"
      assert denied["params"]["reason"] == "finance_channel_not_included"
      assert denied["params"]["nickname"] == plain.nickname

      assert conn
             |> assign_workout(gym, %{
               master_workout_id: wod.id,
               athlete_ids: [unmanaged.id, athlete.id],
               scheduled_for: today
             })
             |> json_response(403)
             |> Map.fetch!("params")
             |> Map.fetch!("reason") == "finance_profile_missing"

      assert my_workouts(conn, gym, plain) == []
      assert my_workouts(conn, gym, athlete) == []

      # ADR-225: the athlete role does not imply the grant either.
      assert conn
             |> assign_workout(gym, %{
               master_workout_id: wod.id,
               athlete_ids: [athlete.id],
               scheduled_for: today
             })
             |> json_response(403)
             |> Map.fetch!("params")
             |> Map.fetch!("user_id") == athlete.id

      # Personal training includes the programme.
      programming_grant_fixture(gym.context, athlete, :personal_training)

      assert conn
             |> assign_workout(gym, %{
               master_workout_id: wod.id,
               athlete_ids: [athlete.id],
               scheduled_for: today
             })
             |> json_response(201)

      # Profile programming refuses before copying, so no orphan copy exists.
      folder =
        conn
        |> api(gym.admin)
        |> post(
          "/api/org/#{slug(gym)}/admin/workout-folders",
          Jason.encode!(%{name: "Personal", parent_id: nil})
        )
        |> json_response(201)

      before = workout_count(gym.context)

      assert conn
             |> api(gym.admin)
             |> post(
               "/api/org/#{slug(gym)}/admin/users/#{plain.id}/programming",
               Jason.encode!(%{
                 master_workout_id: wod.id,
                 folder_id: folder["id"],
                 scheduled_for: today,
                 copy_source: true,
                 mode: "personal"
               })
             )
             |> json_response(403)
             |> Map.fetch!("code") == "programming_not_in_package"

      assert workout_count(gym.context) == before
    end

    test "profile programming assigns an isolated personal copy to an entitled member", %{
      conn: conn
    } do
      gym = tenant("pm_profile")

      member =
        gym
        |> customer(:member, "pm_profile_member")
        |> then(&give_package(gym, &1, @programming_plan))

      wod = workout(gym, "Template")
      day = Date.utc_today() |> Date.add(1) |> Date.to_iso8601()

      folder =
        conn
        |> api(gym.admin)
        |> post(
          "/api/org/#{slug(gym)}/admin/workout-folders",
          Jason.encode!(%{name: "Members", parent_id: nil})
        )
        |> json_response(201)

      programmed =
        conn
        |> api(gym.admin)
        |> post(
          "/api/org/#{slug(gym)}/admin/users/#{member.id}/programming",
          Jason.encode!(%{
            master_workout_id: wod.id,
            folder_id: folder["id"],
            scheduled_for: day,
            copy_source: true,
            mode: "personal"
          })
        )
        |> json_response(201)

      assert programmed["mode"] == "personal"
      assert programmed["workout"]["source_workout_id"] == wod.id
      assert programmed["association"]["assignment_kind"] == "personal"

      schedule =
        conn
        |> api(gym.admin)
        |> get(
          "/api/org/#{slug(gym)}/admin/users/#{member.id}/schedule?start_date=#{day}&end_date=#{day}"
        )
        |> json_response(200)

      assert [%{"kind" => "assignment", "workout" => %{"id" => copy_id}}] = schedule["items"]
      assert copy_id == programmed["workout"]["id"]
    end

    test "without a folder a member's personal copy is filed in their variations folder", %{
      conn: conn
    } do
      gym = tenant("pm_varfolder")

      member =
        gym
        |> customer(:member, "pm_variation_member")
        |> then(&give_package(gym, &1, @programming_plan))

      wod = workout(gym, "Variation template")

      programmed =
        conn
        |> api(gym.admin)
        |> post(
          "/api/org/#{slug(gym)}/admin/users/#{member.id}/programming",
          Jason.encode!(%{
            master_workout_id: wod.id,
            scheduled_for: Date.utc_today() |> Date.add(1) |> Date.to_iso8601(),
            copy_source: true,
            mode: "personal"
          })
        )
        |> json_response(201)

      folders =
        conn
        |> api(gym.admin)
        |> get("/api/org/#{slug(gym)}/admin/workout-folders")
        |> json_response(200)
        |> Map.fetch!("folders")

      by_key = Map.new(folders, &{&1["system_key"], &1})
      member_folder = by_key["member_variations:#{member.id}"]

      assert member_folder["parent_id"] == by_key["member_variations"]["id"]
      assert programmed["workout"]["folder_id"] == member_folder["id"]
      assert programmed["workout"]["source_workout_id"] == wod.id

      # ADR-125: the copy stays out of the shared library listing.
      library_ids =
        conn
        |> api(gym.admin)
        |> get("/api/org/#{slug(gym)}/admin/workouts")
        |> json_response(200)
        |> Map.fetch!("workouts")
        |> Enum.map(& &1["id"])

      refute programmed["workout"]["id"] in library_ids
    end
  end

  describe "class variants" do
    test "only the target member sees their version; the class workout is untouched", %{
      conn: conn
    } do
      gym = tenant("pm_variant")

      member =
        gym
        |> customer(:member, "pm_variant_member")
        |> then(&give_package(gym, &1, @programming_plan))

      classmate =
        gym
        |> customer(:member, "pm_classmate")
        |> then(&give_package(gym, &1, @programming_plan))

      class_wod = workout(gym, "Class WOD")
      slot = booked_class(gym, class_wod, [member, classmate])
      day = slot.scheduled_at |> DateTime.to_date() |> Date.to_iso8601()

      folder =
        conn
        |> api(gym.admin)
        |> post(
          "/api/org/#{slug(gym)}/admin/workout-folders",
          Jason.encode!(%{name: "Variants", parent_id: nil})
        )
        |> json_response(201)

      programmed =
        conn
        |> api(gym.admin)
        |> post(
          "/api/org/#{slug(gym)}/admin/users/#{member.id}/programming",
          Jason.encode!(%{
            folder_id: folder["id"],
            scheduled_for: day,
            slot_id: slot.id,
            copy_source: true,
            mode: "class_variant"
          })
        )
        |> json_response(201)

      variant_workout_id = programmed["workout"]["id"]
      assert programmed["workout"]["source_workout_id"] == class_wod.id
      assert programmed["association"]["assignment_kind"] == "class_variant"
      assert programmed["association"]["source_slot_id"] == slot.id
      assignment_id = programmed["association"]["id"]

      # The class keeps its own workout for everyone.
      assert Scheduling.get_slot(gym.context, slot.id).master_workout_id == class_wod.id

      member_slot = schedule_slot(conn, gym, member, slot.id)
      assert member_slot["master_workout_id"] == class_wod.id
      assert member_slot["my_version"]["assignment_id"] == assignment_id
      assert member_slot["my_version"]["workout"]["id"] == variant_workout_id
      refute Map.has_key?(member_slot, "member_versions")

      classmate_slot = schedule_slot(conn, gym, classmate, slot.id)
      assert classmate_slot["my_version"] == nil
      assert my_workouts(conn, gym, classmate) == []

      staff_slot = schedule_slot(conn, gym, gym.admin, slot.id)

      assert [%{"user_id" => user_id, "user_nickname" => nickname}] =
               staff_slot["member_versions"]

      assert user_id == member.id
      assert nickname == member.nickname

      # The member starts their version through the assigned source; the class
      # booking is unaffected (attendance stays a staff action).
      assert conn
             |> start_assigned(member, variant_workout_id, assignment_id)
             |> json_response(201)
             |> get_in(["execution", "source"]) == "assigned"

      assert [%{user_booking: %{status: booking_status}}] =
               Scheduling.list_member_slots(
                 gym.context,
                 member.id,
                 slot.scheduled_at,
                 DateTime.add(slot.scheduled_at, 1)
               )

      assert to_string(booking_status) == "approved"

      # A classmate cannot borrow the variant.
      assert conn
             |> start_assigned(classmate, variant_workout_id, assignment_id)
             |> json_response(403)

      # Rejecting hides "Your version" from the class card.
      conn
      |> api(member)
      |> patch("/api/org/#{slug(gym)}/my-workouts/assignments/#{assignment_id}/reject")
      |> json_response(200)

      assert schedule_slot(conn, gym, member, slot.id)["my_version"] == nil
    end

    test "a variant needs one member who booked the class", %{conn: conn} do
      gym = tenant("pm_variant_rules")

      member =
        gym
        |> customer(:member, "pm_rule_member")
        |> then(&give_package(gym, &1, @programming_plan))

      other =
        gym
        |> customer(:member, "pm_rule_other")
        |> then(&give_package(gym, &1, @programming_plan))

      class_wod = workout(gym, "Rules WOD")
      variant_wod = workout(gym, "Rules variant")
      slot = booked_class(gym, class_wod, [member])

      assert conn
             |> assign_workout(gym, %{
               master_workout_id: variant_wod.id,
               athlete_ids: [member.id, other.id],
               scheduled_for: Date.utc_today() |> Date.to_iso8601(),
               source_slot_id: slot.id
             })
             |> json_response(422)
             |> Map.fetch!("code") == "class_variant_requires_single_member"

      assert conn
             |> assign_workout(gym, %{
               master_workout_id: variant_wod.id,
               athlete_ids: [other.id],
               scheduled_for: Date.utc_today() |> Date.to_iso8601(),
               source_slot_id: slot.id
             })
             |> json_response(422)
             |> Map.fetch!("code") == "slot_not_booked_by_member"

      created =
        conn
        |> assign_workout(gym, %{
          master_workout_id: variant_wod.id,
          athlete_ids: [member.id],
          scheduled_for: slot.scheduled_at |> DateTime.to_date() |> Date.to_iso8601(),
          source_slot_id: slot.id
        })
        |> json_response(201)
        |> Map.fetch!("assignment")

      assert created["assignment_kind"] == "class_variant"
    end
  end

  describe "tenant isolation" do
    test "another tenant can neither target nor see this tenant's member programming", %{
      conn: conn
    } do
      gym_a = tenant("pm_iso_a")
      gym_b = tenant("pm_iso_b")

      member_a =
        gym_a
        |> customer(:member, "pm_iso_member")
        |> then(&give_package(gym_a, &1, @programming_plan))

      member_b =
        gym_b
        |> customer(:member, "pm_iso_member_b")
        |> then(&give_package(gym_b, &1, @programming_plan))

      class_a = workout(gym_a, "A class")
      variant_a = workout(gym_a, "A variant")
      wod_b = workout(gym_b, "B WOD")
      slot_a = booked_class(gym_a, class_a, [member_a])

      # B's staff cannot address A's member, and A's slot is unknown to B.
      assert conn
             |> assign_workout(gym_b, %{
               master_workout_id: wod_b.id,
               athlete_ids: [member_a.id],
               scheduled_for: Date.utc_today() |> Date.to_iso8601()
             })
             |> json_response(422)
             |> Map.fetch!("code") == "invalid_athletes"

      assert conn
             |> assign_workout(gym_b, %{
               master_workout_id: wod_b.id,
               athlete_ids: [member_b.id],
               scheduled_for: Date.utc_today() |> Date.to_iso8601(),
               source_slot_id: slot_a.id
             })
             |> json_response(404)
             |> Map.fetch!("code") == "slot_not_found"

      created =
        conn
        |> assign_workout(gym_a, %{
          master_workout_id: variant_a.id,
          athlete_ids: [member_a.id],
          scheduled_for: slot_a.scheduled_at |> DateTime.to_date() |> Date.to_iso8601(),
          source_slot_id: slot_a.id
        })
        |> json_response(201)
        |> Map.fetch!("assignment")

      # B's member sees nothing; A's member cannot read B's board.
      assert my_workouts(conn, gym_b, member_b) == []

      assert conn
             |> api(member_a)
             |> get("/api/org/#{slug(gym_b)}/my-workouts")
             |> json_response(404)
             |> Map.fetch!("code") == "organization_context_not_found"

      # B's staff board never lists A's assignment.
      assert conn
             |> api(gym_b.admin)
             |> get("/api/org/#{slug(gym_b)}/my-workouts?start_date=#{Date.utc_today()}")
             |> json_response(200)
             |> Map.fetch!("assignments") == []

      assert Workouts.list_class_variants(gym_b.context, [slot_a.id], nil) == []

      assert [%{assignment_id: id}] =
               Workouts.list_class_variants(gym_a.context, [slot_a.id], nil)

      assert id == created["id"]
    end
  end

  test "the assignee picker can include members", %{conn: conn} do
    gym = tenant("pm_picker")
    member = customer(gym, :member, "pm_picker_member")
    athlete = customer(gym, :athlete, "pm_picker_athlete")

    ids = fn query ->
      conn
      |> api(gym.admin)
      |> get("/api/org/#{slug(gym)}/admin/athletes#{query}")
      |> json_response(200)
      |> Map.fetch!("athletes")
      |> Enum.map(& &1["id"])
      |> Enum.sort()
    end

    assert ids.("") == [athlete.id]
    assert ids.("?include_members=true") == Enum.sort([athlete.id, member.id])
  end

  test "the profile says up front whether a WOD can be assigned, and through which grant", %{
    conn: conn
  } do
    gym = tenant("pm_profile_flag")
    plain = customer(gym, :athlete, "pm_flag_plain")

    online =
      gym
      |> customer(:member, "pm_flag_online")
      |> then(&give_package(gym, &1, @programming_plan))

    pt =
      gym
      |> customer(:athlete, "pm_flag_pt")
      |> then(&programming_grant_fixture(gym.context, &1, :personal_training))

    programming = fn user ->
      conn
      |> api(gym.admin)
      |> get("/api/org/#{slug(gym)}/admin/users/#{user.id}")
      |> json_response(200)
      |> get_in(["user", "programming"])
    end

    assert programming.(plain) == %{
             "allowed" => false,
             "grant" => nil,
             "reason" => "finance_profile_missing"
           }

    assert %{"allowed" => true, "grant" => "online_programming"} = programming.(online)
    assert %{"allowed" => true, "grant" => "personal_training"} = programming.(pt)
    # Staff are not programmed: no flag.
    assert programming.(gym.admin) == nil
  end
end
