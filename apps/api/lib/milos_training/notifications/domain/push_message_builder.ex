defmodule MilosTraining.Notifications.Domain.PushMessageBuilder do
  def build(type, payload) when is_atom(type), do: build(to_string(type), payload)

  def build("booking_pending", payload) do
    %{
      title: "New booking request",
      body: payload["body"] || booking_body(payload),
      url: payload["url"] || "/schedule"
    }
  end

  def build("booking_approved", payload) do
    %{
      title: "Booking approved",
      body: payload["body"] || booking_body(payload),
      url: payload["url"] || "/schedule"
    }
  end

  def build("booking_rejected", payload) do
    %{
      title: "Booking rejected",
      body: payload["body"] || booking_body(payload),
      url: payload["url"] || "/schedule"
    }
  end

  def build("booking_timeout", payload) do
    %{
      title: "Booking timed out",
      body: payload["body"] || booking_body(payload),
      url: payload["url"] || "/schedule"
    }
  end

  def build("workout_note", payload) do
    note = payload["note"] || %{}

    parts =
      [note["selected_text"], note["note_text"]]
      |> Enum.filter(&(is_binary(&1) and &1 != ""))

    %{
      title: "Workout annotation",
      body: Enum.join(parts, " · ") |> default_to("A workout annotation needs review."),
      url: payload["url"] || execution_url(payload)
    }
  end

  def build("workout_changed", payload) do
    %{
      title: "Workout changed",
      body: payload["body"] || "Your coach changed a scheduled workout.",
      url: payload["url"] || "/"
    }
  end

  def build("workout_deleted", payload) do
    %{
      title: "Workout removed",
      body: payload["body"] || "Your coach removed a scheduled workout.",
      url: payload["url"] || "/"
    }
  end

  def build("workout_rejected", payload) do
    nickname = payload["athlete_nickname"] || "An athlete"
    title = payload["workout_title"] || "a workout"

    %{
      title: "Workout rejected",
      body: payload["body"] || "#{nickname} rejected #{title}.",
      url: payload["url"] || "/my-workouts"
    }
  end

  def build("workout_moved", payload) do
    %{
      title: "Workout rescheduled",
      body: payload["body"] || "An athlete rescheduled their workout.",
      url: payload["url"] || "/my-workouts"
    }
  end

  def build("athlete_message", payload) do
    nickname = payload["sender_nickname"] || "An athlete"

    %{
      title: "Message from #{nickname}",
      body: payload["body"] || "#{nickname} sent you a message.",
      url: payload["url"] || payload["context_url"] || "/"
    }
  end

  def build("admin_note", payload) do
    %{
      title: "New coach note",
      body: payload["body"] || "Your coach added a new note.",
      url: payload["url"] || "/#coach-notes"
    }
  end

  def build("challenge_completed", payload) do
    %{
      title: "Challenge completed",
      body: payload["badge_label"] || payload["title"] || "You completed a challenge.",
      url: payload["url"] || "/#challenges"
    }
  end

  def build("chat_message", payload) do
    context =
      if payload["context_type"] in ["assignment", "class_slot"],
        do: " in your workout thread",
        else: ""

    %{
      title: "New message#{context}",
      body: payload["body"] || "You received a new message.",
      url: payload["url"] || "/"
    }
  end

  def build(_type, payload) do
    %{
      title: "Milos Training",
      body: payload["body"] || "You have a new notification.",
      url: payload["url"] || "/"
    }
  end

  defp booking_body(payload) do
    [training_type_label(payload["training_type"]), payload["admin_message"]]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.join(" · ")
    |> default_to("Open the schedule to review the latest booking state.")
  end

  defp training_type_label(nil), do: nil

  defp training_type_label(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp execution_url(%{"execution_id" => execution_id}) when is_binary(execution_id),
    do: "/workouts/#{execution_id}/execute"

  defp execution_url(_payload), do: "/"

  defp default_to("", fallback), do: fallback
  defp default_to(value, _fallback), do: value
end
