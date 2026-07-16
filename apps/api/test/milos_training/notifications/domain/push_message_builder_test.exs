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

    assert message.title == "Booking approved"
    assert message.body =~ "CrossFit Foundations"
    assert message.url == "/schedule"
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
