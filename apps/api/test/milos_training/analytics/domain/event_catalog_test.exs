defmodule MilosTraining.Analytics.Domain.EventCatalogTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Analytics.Domain.EventCatalog

  @org "11111111-1111-1111-1111-111111111111"
  @user "22222222-2222-2222-2222-222222222222"
  @subject "33333333-3333-3333-3333-333333333333"
  @at ~U[2026-10-12 08:30:00.000000Z]

  test "registry keeps the Phase 8 events and adds the ADR-113 families" do
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
end
