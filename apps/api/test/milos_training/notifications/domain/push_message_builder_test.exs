defmodule MilosTraining.Notifications.Domain.PushMessageBuilderTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Notifications.Domain.PushMessageBuilder

  test "builds workout note copy with selected text and route" do
    message =
      PushMessageBuilder.build("workout_note", %{
        "execution_id" => "execution-123",
        "note" => %{
          "selected_text" => "Push Press",
          "note_text" => "Felt unstable overhead"
        }
      })

    assert message.title == "Workout annotation"
    assert message.body =~ "Push Press"
    assert message.body =~ "Felt unstable overhead"
    assert message.url == "/workouts/execution-123/execute"
  end

  test "builds booking approval copy with schedule route" do
    message =
      PushMessageBuilder.build("booking_approved", %{
        "class_type_name" => "CrossFit Foundations"
      })

    assert message.title == "Class bookings approved"
    assert message.body =~ "one or more"
    assert message.url == "/schedule"
  end

  test "builds consolidated workout assignment copy with athlete route" do
    message = PushMessageBuilder.build("workout_assigned", %{})

    assert message.title == "New workouts assigned"
    assert message.body =~ "one or more"
    assert message.url == "/my-workouts"
  end

  test "builds workout assignment request copy with personal coaching route" do
    message =
      PushMessageBuilder.build("workout_assignment_requested", %{
        "athlete_nickname" => "Atlas",
        "requested_for" => "2026-07-21",
        "note" => "Strength focus"
      })

    assert message.title == "Workout assignment requested"
    assert message.body =~ "Atlas"
    assert message.body =~ "2026-07-21"
    assert message.url == "/admin/coaching-assignments?date=2026-07-21"
  end

  test "builds review submission copy with admin reviews route" do
    message =
      PushMessageBuilder.build("review_submitted", %{
        "rating" => 4,
        "target_type" => "class_slot"
      })

    assert message.title == "New review submitted"
    assert message.body =~ "4/5"
    assert message.url == "/admin/reviews"
  end

  test "renders system copy through the supplied locale function while preserving authored text" do
    localize = fn message, bindings ->
      "el:" <>
        Enum.reduce(bindings, message, fn {key, value}, copy ->
          String.replace(copy, "%{#{key}}", to_string(value))
        end)
    end

    message =
      PushMessageBuilder.build(
        "athlete_message",
        %{"sender_nickname" => "Νίκη", "body" => "User-authored body"},
        localize
      )

    assert message.title == "el:Message from Νίκη"
    assert message.body == "User-authored body"
  end
end
