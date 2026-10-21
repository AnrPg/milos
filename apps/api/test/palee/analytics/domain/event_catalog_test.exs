defmodule Palee.Analytics.Domain.EventCatalogTest do
  use ExUnit.Case, async: true

  alias Palee.Analytics.Domain.EventCatalog

  @org "11111111-1111-1111-1111-111111111111"
  @user "22222222-2222-2222-2222-222222222222"
  @subject "33333333-3333-3333-3333-333333333333"
  @at ~U[2026-10-12 08:30:00.000000Z]

  test "registry keeps the Phase 8 events and adds the ADR-123 families" do
    names = EventCatalog.event_names()

    for name <- ~w(payment_recorded review_submitted notification_clicked finance_invoice_created) do
      assert name in names
    end

    for name <- ~w(workout_published workout_assignment_opened workout_execution_abandoned
                   execution_interaction class_booking_requested messaging_first_staff_response
                   notification_push_outcome notification_in_app_delivered) do
      assert name in EventCatalog.instrumented_event_names()
    end

    refute EventCatalog.registered?("workout_publishd")
    refute EventCatalog.registered?(nil)
  end

  test "build/4 rejects unknown event names" do
    assert {:error, :unknown_analytics_event} = EventCatalog.build("nope", nil, %{}, %{})
  end

  test "build/4 derives tenant, actor, context and registered subject metadata" do
    actor = %{organization_id: @org, user_id: @user, role: :admin}

    subject = %{
      id: @subject,
      type: :crossfit,
      authoring_mode: "structured",
      is_team_workout: false,
      title: "Murph",
      description: String.duplicate("x", 500)
    }

    assert {:ok, attrs} =
             EventCatalog.build("workout_published", actor, subject, %{
               occurred_at: @at,
               metadata: %{affected_assignment_count: 2, notes: %{"free" => "text"}}
             })

    assert attrs.organization_id == @org
    assert attrs.user_id == @user
    assert attrs.actor_role_snapshot == "admin"
    assert attrs.context_type == "workout"
    assert attrs.context_id == @subject
    assert attrs.occurred_at == @at
    refute Map.has_key?(attrs, :dedupe_key)

    assert attrs.metadata == %{
             "type" => "crossfit",
             "authoring_mode" => "structured",
             "is_team_workout" => false,
             "affected_assignment_count" => 2
           }
  end

  test "sanitize/1 drops free text, nested maps and lists" do
    assert EventCatalog.sanitize(%{
             ok: "short_enum",
             long: String.duplicate("a", 65),
             nested: %{a: 1},
             list: [1, 2],
             date: ~D[2026-10-12],
             nil_value: nil
           }) == %{"ok" => "short_enum", "date" => "2026-10-12"}
  end

  test "subject dedupe collapses replays of the same subject" do
    assert {:ok, %{dedupe_key: @subject}} =
             EventCatalog.build("workout_execution_abandoned", nil, %{id: @subject}, %{
               organization_id: @org
             })
  end

  test "user/subject/day dedupe uses the UTC day of occurred_at" do
    actor = %{organization_id: @org, user_id: @user}

    assert {:ok, %{dedupe_key: key}} =
             EventCatalog.build("workout_assignment_opened", actor, %{id: @subject}, %{
               occurred_at: @at
             })

    assert key == "#{@user}:#{@subject}:2026-10-12"
  end

  test "explicit dedupe requires a caller-supplied key" do
    assert {:ok, attrs} =
             EventCatalog.build("execution_interaction", nil, %{id: @subject}, %{
               organization_id: @org,
               dedupe_key: "#{@user}:abc"
             })

    assert attrs.dedupe_key == "#{@user}:abc"

    assert {:ok, attrs} =
             EventCatalog.build("execution_interaction", nil, %{id: @subject}, %{
               organization_id: @org
             })

    refute Map.has_key?(attrs, :dedupe_key)
  end

  describe "ADR-124 injury warning events" do
    test "are registered as workout-scoped, explicitly deduped events" do
      for name <- ~w(injury_warning_shown injury_warning_acknowledged) do
        assert name in EventCatalog.instrumented_event_names()
      end

      assert {:ok, attrs} =
               EventCatalog.build(
                 "injury_warning_shown",
                 %{organization_id: @org, user_id: @user, role: :admin},
                 %{id: @subject},
                 %{dedupe_key: "k", occurred_at: @at, metadata: %{audience: "staff"}}
               )

      assert attrs.context_type == "workout"
      assert attrs.context_id == @subject
      assert attrs.dedupe_key == "k"
    end

    test "metadata is restricted to the injury allowlist (enums, counts, ids only)" do
      assert {:ok, attrs} =
               EventCatalog.build("injury_warning_acknowledged", %{organization_id: @org}, nil, %{
                 context_id: @subject,
                 metadata: %{
                   audience: "self",
                   surface: "assignment_detail",
                   warning_level: "avoid",
                   injury_warning_count: 2,
                   avoid_exercise_count: 1,
                   caution_exercise_count: 3,
                   athlete_id: @user,
                   body_area: "left knee",
                   training_limitations: "no squats",
                   note: "x"
                 }
               })

      assert attrs.metadata == %{
               "audience" => "self",
               "surface" => "assignment_detail",
               "warning_level" => "avoid",
               "injury_warning_count" => 2,
               "avoid_exercise_count" => 1,
               "caution_exercise_count" => 3,
               "athlete_id" => @user
             }
    end

    test "execution completion accepts the injury segmentation facts" do
      assert "had_active_injury" in EventCatalog.injury_segmentation_keys()
      assert "injury_warning_level" in EventCatalog.injury_segmentation_keys()

      assert {:ok, attrs} =
               EventCatalog.build("workout_execution_completed", nil, %{id: @subject}, %{
                 organization_id: @org,
                 metadata: %{had_active_injury: true, injury_warning_level: "caution"}
               })

      assert attrs.metadata["had_active_injury"] == true
      assert attrs.metadata["injury_warning_level"] == "caution"
    end

    test "the injury allowlist keeps the evaluated scale level (TD-088)" do
      assert "scale_level_slug" in EventCatalog.injury_warning_metadata_keys()

      assert {:ok, attrs} =
               EventCatalog.build("injury_warning_shown", %{organization_id: @org}, nil, %{
                 context_id: @subject,
                 metadata: %{audience: "self", surface: "pre_start", scale_level_slug: "scaled"}
               })

      assert attrs.metadata["scale_level_slug"] == "scaled"
    end

    test "abandonment and training-log events accept the injury facts (TD-088)" do
      keys = EventCatalog.injury_segmentation_keys()

      for key <- ~w(had_active_injury injury_warning_level injury_warning_shown
                    injury_warning_acknowledged) do
        assert key in keys
      end

      metadata = %{
        had_active_injury: true,
        injury_warning_level: "avoid",
        injury_warning_shown: true,
        injury_warning_acknowledged: false
      }

      assert {:ok, abandoned} =
               EventCatalog.build("workout_execution_abandoned", nil, %{id: @subject}, %{
                 organization_id: @org,
                 metadata: metadata
               })

      assert abandoned.metadata["injury_warning_shown"] == true
      assert abandoned.metadata["injury_warning_acknowledged"] == false

      assert {:ok, logged} =
               EventCatalog.build("training_log_entry_logged", nil, %{id: @subject}, %{
                 organization_id: @org,
                 metadata: Map.take(metadata, [:had_active_injury, :injury_warning_level])
               })

      assert logged.metadata["had_active_injury"] == true
      assert logged.metadata["injury_warning_level"] == "avoid"
    end
  end
end
