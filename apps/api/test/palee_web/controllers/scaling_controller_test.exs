defmodule Palee.Web.ScalingControllerTest do
  @moduledoc """
  ADR-174 (P3-M12): AI scaling suggestions end to end. Off by default; the
  gym's own key is write-only; an injured athlete's assignment yields a
  pending suggestion in the queue of the coaches who manage them; the member
  sees nothing until a coach approves, and then only the approved changes.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Application.{AdminReportInjury, ReportInjury, ScalingSuggestions}
  alias Palee.{AiUsage, Coaching, Organizations, Repo, Workouts}
  alias Palee.Scaling.ScalingSuggestion

  @key "sk-ant-test-0123456789abcdef"

  setup %{conn: conn} do
    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Scaling Gym #{System.unique_integer([:positive])}"
      })

    person = fn role ->
      user = user_fixture()

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

    owner = person.(:owner)
    coach = person.(:coach)
    other_coach = person.(:coach)
    athlete = person.(:athlete)
    {:ok, owner_context} = Organizations.resolve_tenant_context(owner, organization.slug)
    {:ok, athlete_context} = Organizations.resolve_tenant_context(athlete, organization.slug)
    {:ok, _levels} = Workouts.seed_default_scale_levels(owner_context)

    {:ok, workout} =
      Workouts.create_workout(owner_context, owner, %{
        title: "Legs and press",
        type: :crossfit,
        sections: [
          %{
            name: "Strength",
            order: 1,
            scoreable: false,
            exercises: [
              %{
                name: "Back Squat",
                order: 1,
                sets: 5,
                prescription_value: 5,
                prescription_unit: "reps"
              },
              %{
                name: "Strict Press",
                order: 2,
                sets: 5,
                prescription_value: 5,
                prescription_unit: "reps"
              }
            ]
          }
        ]
      })

    {:ok, assignment} =
      Workouts.assign_workout(owner_context, %{
        master_workout_id: workout.id,
        athlete_ids: [athlete.id],
        scheduled_for: Date.add(Date.utc_today(), 1)
      })

    {:ok, _relationship} =
      Coaching.start_relationship(%{organization_id: organization.id}, %{
        coach_user_id: coach.id,
        client_user_id: athlete.id,
        origin: "assigned"
      })

    %{
      organization: organization,
      owner: owner,
      owner_context: owner_context,
      coach: coach,
      other_coach: other_coach,
      athlete: athlete,
      athlete_context: athlete_context,
      workout: workout,
      assignment: assignment,
      as: fn user -> put_bearer_token(conn, user) end,
      admin: "/api/org/#{organization.slug}/admin",
      staff: "/api/org/#{organization.slug}/staff",
      me: "/api/org/#{organization.slug}/me"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp knee!(ctx) do
    {:ok, injury} =
      AdminReportInjury.call(ctx.owner_context, ctx.owner.id, ctx.athlete.id, %{
        "body_area" => "knee",
        "severity" => "moderate",
        "visibility" => "user_and_admin"
      })

    injury
  end

  defp enable!(ctx, key \\ @key) do
    ctx.as.(ctx.owner)
    |> send_json("put", "#{ctx.admin}/ai-settings", %{api_key: key, scaling_enabled: true})
    |> json_response(200)
  end

  defp scan(ctx), do: ScalingSuggestions.scan(ctx.owner_context, Date.utc_today())

  defp member_scaling(ctx) do
    ctx.as.(ctx.athlete)
    |> get("#{ctx.me}/workouts/#{ctx.workout.id}/scaling")
    |> json_response(200)
    |> Map.fetch!("scaling")
  end

  describe "AI settings" do
    test "off by default; the key is write-only; switching on needs a key", ctx do
      body = ctx.as.(ctx.owner) |> get("#{ctx.admin}/ai-settings") |> json_response(200)

      assert %{
               "ai_settings" => %{
                 "scaling_enabled" => false,
                 "key_configured" => false,
                 "default_model" => "claude-sonnet-5-5",
                 "usage" => %{"suggestions" => 0}
               }
             } = body

      assert %{"code" => "api_key_required"} =
               ctx.as.(ctx.owner)
               |> send_json("put", "#{ctx.admin}/ai-settings", %{scaling_enabled: true})
               |> json_response(422)

      %{"ai_settings" => settings} = enable!(ctx)
      assert settings["key_configured"]
      assert settings["key_last4"] == "cdef"
      refute Map.has_key?(settings, "api_key")
      refute inspect(settings) =~ @key

      # Stored encrypted, read back plain only on the server.
      raw = Repo.query!("SELECT api_key FROM organization_ai_settings").rows |> List.flatten()
      refute Enum.any?(raw, &(is_binary(&1) and &1 =~ @key))
      assert %{api_key: @key} = AiUsage.get_settings(ctx.owner_context)

      %{"ai_settings" => removed} =
        ctx.as.(ctx.owner)
        |> send_json("put", "#{ctx.admin}/ai-settings", %{remove_key: true})
        |> json_response(200)

      refute removed["key_configured"]
      refute removed["scaling_enabled"]
    end

    test "only settings managers reach it", ctx do
      ctx.as.(ctx.coach) |> get("#{ctx.admin}/ai-settings") |> json_response(403)
    end
  end

  describe "suggestions" do
    test "nothing runs while the gym has not switched scaling on", ctx do
      knee!(ctx)
      assert scan(ctx) == []
      refute_received {:scaling_advisor_called, _input, _options}
    end

    test "approval is mandatory: pending is coach-only, approved reaches the member", ctx do
      knee!(ctx)
      enable!(ctx)

      assert [{_assignment, _athlete}] = scan(ctx)
      assert_received {:scaling_advisor_called, input, options}

      # The gym's own key, the default model, metered per gym.
      assert options.api_key == @key
      assert options.model == "claude-sonnet-5-5"
      assert options.metering.feature == "scaling_suggestions"
      # Data minimisation: no athlete identity in what the advisor sees.
      refute inspect(input) =~ ctx.athlete.id
      assert [%{body_area: "knee"}] = input.injuries
      assert Enum.any?(input.flagged_movements, &(&1.name == "Back Squat"))

      # Pending: invisible to the member.
      assert member_scaling(ctx) == nil

      # The athlete's coach sees it; another coach does not.
      assert %{"suggestions" => []} =
               ctx.as.(ctx.other_coach)
               |> get("#{ctx.staff}/scaling-suggestions")
               |> json_response(200)

      %{"suggestions" => [suggestion]} =
        ctx.as.(ctx.coach) |> get("#{ctx.staff}/scaling-suggestions") |> json_response(200)

      assert suggestion["status"] == "pending"
      assert suggestion["workout_title"] == "Legs and press"
      assert suggestion["scale_level_slug"] == "scaled"
      assert "knee" in suggestion["injury_regions"]
      # The advisor's change to a movement outside the workout was dropped.
      assert [%{"exercise_name" => "Back Squat", "change" => "substitute", "id" => item_id}] =
               suggestion["items"]

      # Another coach cannot act on it.
      ctx.as.(ctx.other_coach)
      |> send_json("post", "#{ctx.staff}/scaling-suggestions/#{suggestion["id"]}/approve", %{})
      |> json_response(404)

      %{"suggestion" => approved} =
        ctx.as.(ctx.coach)
        |> send_json("post", "#{ctx.staff}/scaling-suggestions/#{suggestion["id"]}/approve", %{
          items: [%{id: item_id, suggested: "Goblet box squat"}],
          coach_note: "Πάμε ήπια σήμερα."
        })
        |> json_response(200)

      assert approved["status"] == "approved"

      assert %{
               "coach_note" => "Πάμε ήπια σήμερα.",
               "scale_level_slug" => "scaled",
               "scale_level_label" => "Scaled",
               "items" => [%{"exercise_name" => "Back Squat", "suggested" => "Goblet box squat"}],
               "modifications" => [patch]
             } = member_scaling(ctx)

      # ADR-050 patch on the exact row.
      assert %{
               "type" => "exercise_substituted",
               "field" => "exercise_name",
               "canonical_value" => "Back Squat",
               "actual_value" => "Goblet box squat"
             } = patch

      assert {:ok, _normalized} = Palee.Execution.normalize_modification(patch)

      # A second review conflicts.
      ctx.as.(ctx.coach)
      |> send_json("post", "#{ctx.staff}/scaling-suggestions/#{suggestion["id"]}/dismiss", %{})
      |> json_response(409)

      # Decided suggestions are never regenerated.
      assert {:ok, :skipped} =
               ScalingSuggestions.generate(
                 ctx.owner_context,
                 ctx.assignment.id,
                 ctx.athlete.id
               )
    end

    test "a dismissed suggestion never reaches the member", ctx do
      knee!(ctx)
      enable!(ctx)
      scan(ctx)

      %{"suggestions" => [suggestion]} =
        ctx.as.(ctx.owner) |> get("#{ctx.staff}/scaling-suggestions") |> json_response(200)

      ctx.as.(ctx.owner)
      |> send_json("post", "#{ctx.staff}/scaling-suggestions/#{suggestion["id"]}/dismiss", %{})
      |> json_response(200)

      assert member_scaling(ctx) == nil
    end

    test "a personal self-report never reaches the gym's advisor", ctx do
      {:ok, _injury} =
        ReportInjury.call(ctx.athlete_context, ctx.athlete.id, %{
          "body_area" => "knee",
          "severity" => "severe"
        })

      enable!(ctx)
      assert scan(ctx) == []
      refute_received {:scaling_advisor_called, _input, _options}
    end

    test "same inputs are asked once; changed injuries replace a pending answer", ctx do
      knee!(ctx)
      enable!(ctx)
      scan(ctx)
      assert_received {:scaling_advisor_called, _input, _options}

      scan(ctx)
      refute_received {:scaling_advisor_called, _input, _options}

      {:ok, _shoulder} =
        AdminReportInjury.call(ctx.owner_context, ctx.owner.id, ctx.athlete.id, %{
          "body_area" => "shoulder",
          "severity" => "moderate",
          "visibility" => "user_and_admin"
        })

      scan(ctx)
      assert_received {:scaling_advisor_called, _input, _options}

      statuses =
        ScalingSuggestion
        |> Repo.all(skip_tenant_check: true)
        |> Enum.map(& &1.status)
        |> Enum.sort()

      assert statuses == ["pending", "superseded"]
    end

    test "a rejected key stops the feature until a new key is set", ctx do
      knee!(ctx)
      enable!(ctx, "rejected-key-0123456789abcdef")

      # Inline in tests: the scan's generation meets the rejected key.
      assert [{assignment_id, athlete_id}] = scan(ctx)
      assert_received {:scaling_advisor_called, _input, _options}

      assert {:error, :scaling_disabled} =
               ScalingSuggestions.generate(ctx.owner_context, assignment_id, athlete_id)

      assert %{"ai_settings" => %{"key_status" => "rejected"}} =
               ctx.as.(ctx.owner) |> get("#{ctx.admin}/ai-settings") |> json_response(200)

      assert scan(ctx) == []
      assert %{"ai_settings" => %{"key_status" => "unknown"}} = enable!(ctx)
    end

    test "an answer with nothing to change stays out of the queue", ctx do
      knee!(ctx)
      enable!(ctx, "quiet-key-0123456789abcdef")
      scan(ctx)

      assert %{"suggestions" => []} =
               ctx.as.(ctx.owner) |> get("#{ctx.staff}/scaling-suggestions") |> json_response(200)
    end
  end
end
