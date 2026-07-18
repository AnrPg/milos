defmodule MilosTraining.Notifications.Domain.PushMessageBuilder do
  @type localizer :: (String.t(), map() -> String.t())

  def build(type, payload, localize \\ &default_localize/2)

  def build(type, payload, localize) when is_atom(type),
    do: build(to_string(type), payload, localize)

  def build("booking_pending", payload, localize) do
    %{
      title: localize.("New booking request", %{}),
      body: payload["body"] || booking_body(payload, localize),
      url: payload["url"] || "/schedule"
    }
  end

  def build("booking_approved", payload, localize) do
    %{
      title: localize.("Booking approved", %{}),
      body: payload["body"] || booking_body(payload, localize),
      url: payload["url"] || "/schedule"
    }
  end

  def build("booking_rejected", payload, localize) do
    %{
      title: localize.("Booking rejected", %{}),
      body: payload["body"] || booking_body(payload, localize),
      url: payload["url"] || "/schedule"
    }
  end

  def build("booking_timeout", payload, localize) do
    %{
      title: localize.("Booking timed out", %{}),
      body: payload["body"] || booking_body(payload, localize),
      url: payload["url"] || "/schedule"
    }
  end

  def build("workout_note", payload, localize) do
    note = payload["note"] || %{}

    parts =
      [note["selected_text"], note["note_text"]]
      |> Enum.filter(&(is_binary(&1) and &1 != ""))

    %{
      title: localize.("Workout annotation", %{}),
      body:
        Enum.join(parts, " · ")
        |> default_to(localize.("A workout annotation needs review.", %{})),
      url: payload["url"] || execution_url(payload)
    }
  end

  def build("workout_changed", payload, localize) do
    %{
      title: localize.("Workout changed", %{}),
      body: payload["body"] || localize.("Your coach changed a scheduled workout.", %{}),
      url: payload["url"] || "/"
    }
  end

  def build("workout_deleted", payload, localize) do
    %{
      title: localize.("Workout removed", %{}),
      body: payload["body"] || localize.("Your coach removed a scheduled workout.", %{}),
      url: payload["url"] || "/"
    }
  end

  def build("workout_rejected", payload, localize) do
    nickname = payload["athlete_nickname"] || localize.("An athlete", %{})
    title = payload["workout_title"] || localize.("a workout", %{})

    %{
      title: localize.("Workout rejected", %{}),
      body:
        payload["body"] ||
          localize.("%{nickname} rejected %{title}.", %{nickname: nickname, title: title}),
      url: payload["url"] || "/my-workouts"
    }
  end

  def build("workout_moved", payload, localize) do
    %{
      title: localize.("Workout rescheduled", %{}),
      body: payload["body"] || localize.("An athlete rescheduled their workout.", %{}),
      url: payload["url"] || "/my-workouts"
    }
  end

  def build("workout_assignment_requested", payload, localize) do
    nickname = payload["athlete_nickname"] || localize.("An athlete", %{})
    requested_for = payload["requested_for"] || localize.("a requested date", %{})
    note = payload["note"]

    body =
      localize.("%{nickname} requested a workout assignment for %{requested_for}.", %{
        nickname: nickname,
        requested_for: requested_for
      })

    %{
      title: localize.("Workout assignment requested", %{}),
      body: append_note(body, note),
      url:
        payload["url"] ||
          "/admin/coaching-assignments?date=#{requested_for}"
    }
  end

  def build("review_submitted", payload, localize) do
    rating = payload["rating"]
    target_type = payload["target_type"] || localize.("general", %{})

    body =
      if is_integer(rating) do
        localize.("A %{target_type} review was submitted with a %{rating}/5 rating.", %{
          target_type: target_type,
          rating: rating
        })
      else
        localize.("A new %{target_type} review needs attention.", %{target_type: target_type})
      end

    %{
      title: localize.("New review submitted", %{}),
      body: payload["body"] || body,
      url: payload["url"] || "/admin/reviews"
    }
  end

  def build("athlete_message", payload, localize) do
    nickname = payload["sender_nickname"] || localize.("An athlete", %{})

    %{
      title: localize.("Message from %{nickname}", %{nickname: nickname}),
      body:
        payload["body"] || localize.("%{nickname} sent you a message.", %{nickname: nickname}),
      url: payload["url"] || payload["context_url"] || "/"
    }
  end

  def build("admin_note", payload, localize) do
    %{
      title: localize.("New coach note", %{}),
      body: payload["body"] || localize.("Your coach added a new note.", %{}),
      url: payload["url"] || "/#coach-notes"
    }
  end

  def build("challenge_completed", payload, localize) do
    %{
      title: localize.("Challenge completed", %{}),
      body:
        payload["badge_label"] || payload["title"] || localize.("You completed a challenge.", %{}),
      url: payload["url"] || "/#challenges"
    }
  end

  def build("invoice_issued", payload, localize) do
    invoice_number = payload["invoice_number"] || localize.("invoice", %{})

    %{
      title: localize.("New invoice", %{}),
      body:
        payload["body"] ||
          localize.("Invoice %{invoice_number} has been issued for your account.", %{
            invoice_number: invoice_number
          }),
      url: payload["url"] || "/account/billing"
    }
  end

  def build("payment_reminder", payload, localize) do
    cents = payload["outstanding_balance_cents"] || 0
    amount = "€" <> :erlang.float_to_binary(cents / 100, decimals: 2)

    %{
      title: localize.("Payment reminder", %{}),
      body:
        payload["body"] ||
          localize.("You have an outstanding balance of %{amount} due.", %{amount: amount}),
      url: payload["url"] || "/account/billing"
    }
  end

  def build("chat_message", payload, localize) do
    title =
      if payload["context_type"] in ["assignment", "class_slot"],
        do: localize.("New message in your workout thread", %{}),
        else: localize.("New message", %{})

    %{
      title: title,
      body: payload["body"] || localize.("You received a new message.", %{}),
      url: payload["url"] || "/"
    }
  end

  def build(_type, payload, localize) do
    %{
      title: localize.("Milos Training", %{}),
      body: payload["body"] || localize.("You have a new notification.", %{}),
      url: payload["url"] || "/"
    }
  end

  defp booking_body(payload, localize) do
    [payload["class_type_name"], payload["admin_message"]]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.join(" · ")
    |> default_to(localize.("Open the schedule to review the latest booking state.", %{}))
  end

  defp execution_url(%{"execution_id" => execution_id}) when is_binary(execution_id),
    do: "/workouts/#{execution_id}/execute"

  defp execution_url(_payload), do: "/"

  defp default_to("", fallback), do: fallback
  defp default_to(value, _fallback), do: value

  defp append_note(body, note) when is_binary(note) and note != "", do: body <> " " <> note
  defp append_note(body, _note), do: body

  defp default_localize(message, bindings) do
    Enum.reduce(bindings, message, fn {key, value}, copy ->
      String.replace(copy, "%{#{key}}", to_string(value))
    end)
  end
end
