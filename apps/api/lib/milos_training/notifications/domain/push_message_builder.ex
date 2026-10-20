defmodule MilosTraining.Notifications.Domain.PushMessageBuilder do
  alias MilosTraining.Organizations.Domain.AdminPath

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
      title: localize.("Class bookings approved", %{}),
      body:
        payload["body"] ||
          localize.("Your coach approved one or more class booking requests.", %{}),
      url: payload["url"] || "/schedule"
    }
  end

  def build("workout_assigned", payload, localize) do
    %{
      title: localize.("New workouts assigned", %{}),
      body: payload["body"] || localize.("Your coach assigned one or more workouts to you.", %{}),
      url: payload["url"] || "/my-workouts"
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
          admin_url("/admin/coaching-assignments?date=#{requested_for}", payload)
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
      url: payload["url"] || admin_url("/admin/reviews", payload)
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

  def build("coaching_message", payload, localize) do
    %{
      title: localize.("Message from your coach", %{}),
      body: payload["body"] || localize.("Your coach sent you a message.", %{}),
      url: payload["url"] || "/box/coach"
    }
  end

  def build("box_message", payload, localize) do
    %{
      title: localize.("Message from the box", %{}),
      body: payload["body"] || localize.("Your gym sent you a message.", %{}),
      url: payload["url"] || "/"
    }
  end

  def build("follow_requested", payload, localize) do
    %{
      title: localize.("Follow request", %{}),
      body:
        localize.("%{nickname} wants to follow you.", %{nickname: payload["follower_nickname"]}),
      url: payload["url"] || "/me/follow-requests"
    }
  end

  def build("follow_accepted", payload, localize) do
    %{
      title: localize.("Follow request accepted", %{}),
      body: localize.("You now follow %{nickname}.", %{nickname: payload["person_nickname"]}),
      url: payload["url"] || "/people/#{payload["person_id"]}"
    }
  end

  # ADR-144: trials.
  def build("trial_requested", payload, localize) do
    %{
      title: localize.("Trial request", %{}),
      body:
        localize.("%{nickname} asks to try %{class} (%{when}).", %{
          nickname: payload["person_nickname"],
          class: payload["class_name"],
          when: payload["class_when"] || payload["class_starts_at"]
        }),
      url: payload["url"] || "/admin/trials"
    }
  end

  def build("trial_booked", payload, localize) do
    %{
      title: localize.("New trial", %{}),
      body:
        localize.("%{nickname} booked a trial in %{class} (%{when}).", %{
          nickname: payload["person_nickname"],
          class: payload["class_name"],
          when: payload["class_when"] || payload["class_starts_at"]
        }),
      url: payload["url"] || "/admin/trials"
    }
  end

  def build("trial_cancelled", payload, localize) do
    %{
      title: localize.("Trial cancelled", %{}),
      body:
        localize.("%{nickname} cancelled their trial in %{class}.", %{
          nickname: payload["person_nickname"],
          class: payload["class_name"]
        }),
      url: payload["url"] || "/admin/trials"
    }
  end

  def build("trial_accepted", payload, localize) do
    %{
      title: localize.("Your trial is booked", %{}),
      body:
        localize.("%{box}: %{class} (%{when}).", %{
          box: payload["box_name"],
          class: payload["class_name"],
          when: payload["class_when"] || payload["class_starts_at"]
        }),
      url: payload["url"] || "/"
    }
  end

  def build("trial_declined", payload, localize) do
    %{
      title: localize.("Trial not accepted", %{}),
      body:
        localize.("%{box} couldn't take you in %{class}.", %{
          box: payload["box_name"],
          class: payload["class_name"]
        }),
      url: payload["url"] || "/"
    }
  end

  def build("trial_reminder", payload, localize) do
    %{
      title: localize.("Your trial is soon", %{}),
      body:
        localize.("%{class} at %{box} (%{when}).", %{
          box: payload["box_name"],
          class: payload["class_name"],
          when: payload["class_when"] || payload["class_starts_at"]
        }),
      url: payload["url"] || "/"
    }
  end

  def build("trial_follow_up", payload, localize) do
    %{
      title: localize.("How was your trial?", %{}),
      body:
        localize.("Want to keep training at %{box}? Send them a message.", %{
          box: payload["box_name"]
        }),
      url: payload["url"] || "/"
    }
  end

  def build("trial_class_cancelled", payload, localize) do
    %{
      title: localize.("Trial class cancelled", %{}),
      body:
        localize.("%{box} cancelled %{class} (%{when}). Pick another class.", %{
          box: payload["box_name"],
          class: payload["class_name"],
          when: payload["class_when"] || payload["class_starts_at"]
        }),
      url: payload["url"] || "/"
    }
  end

  # ADR-143: member groups, open clubs and reports.
  def build("community_group_proposed", payload, localize) do
    %{
      title: localize.("New group to review", %{}),
      body:
        localize.("%{nickname} wants to start «%{group}».", %{
          nickname: payload["person_nickname"],
          group: payload["group_name"]
        }),
      url: payload["url"] || "/admin/community"
    }
  end

  def build("community_group_approved", payload, localize) do
    %{
      title: localize.("Your group is live", %{}),
      body: localize.("«%{group}» is open. Invite people in.", %{group: payload["group_name"]}),
      url: payload["url"] || "/"
    }
  end

  def build("community_group_declined", payload, localize) do
    %{
      title: localize.("Group not approved", %{}),
      body: localize.("The box didn't approve «%{group}».", %{group: payload["group_name"]}),
      url: payload["url"] || "/"
    }
  end

  def build("community_group_join_requested", payload, localize) do
    %{
      title: localize.("Request to join", %{}),
      body:
        localize.("%{nickname} asks to join «%{group}».", %{
          nickname: payload["person_nickname"],
          group: payload["group_name"]
        }),
      url: payload["url"] || "/"
    }
  end

  def build("community_group_join_approved", payload, localize) do
    %{
      title: localize.("You're in", %{}),
      body: localize.("You joined «%{group}».", %{group: payload["group_name"]}),
      url: payload["url"] || "/"
    }
  end

  def build("community_group_archive_warning", payload, localize) do
    %{
      title: localize.("Your group is quiet", %{}),
      body:
        localize.(
          "Nobody has posted in «%{group}» for a while. Post something or it will be archived.",
          %{
            group: payload["group_name"]
          }
        ),
      url: payload["url"] || "/"
    }
  end

  def build("community_report_created", payload, localize) do
    %{
      title: localize.("New report", %{}),
      body: localize.("Someone reported something in the club.", %{}),
      url: payload["url"] || "/admin/community?tab=reports"
    }
  end

  def build("community_club_join_requested", payload, localize) do
    %{
      title: localize.("Request to join", %{}),
      body:
        localize.("%{nickname} asks to join «%{group}».", %{
          nickname: payload["person_nickname"],
          group: payload["club_name"]
        }),
      url: payload["url"] || "/admin/community?tab=clubs"
    }
  end

  def build("community_club_join_approved", payload, localize) do
    %{
      title: localize.("You're in", %{}),
      body: localize.("You joined «%{group}».", %{group: payload["club_name"]}),
      url: payload["url"] || "/"
    }
  end

  # ADR-153: club events.
  def build("community_event_waitlist_promoted", payload, localize) do
    %{
      title: localize.("A place opened up", %{}),
      body: localize.("You're going to «%{event}» (%{when}).", event_bindings(payload)),
      url: payload["url"] || "/"
    }
  end

  def build("community_event_cancelled", payload, localize) do
    body =
      case payload["reason"] do
        reason when is_binary(reason) and reason != "" ->
          localize.(
            "«%{event}» (%{when}) was cancelled: %{reason}",
            Map.put(event_bindings(payload), :reason, reason)
          )

        _none ->
          localize.("«%{event}» (%{when}) was cancelled.", event_bindings(payload))
      end

    %{title: localize.("Event cancelled", %{}), body: body, url: payload["url"] || "/"}
  end

  def build("community_event_changed", payload, localize) do
    changes = String.split(payload["changes"] || "", ",", trim: true)

    body =
      cond do
        "time" in changes and "place" in changes ->
          localize.("«%{event}» has a new time and place: %{when}.", event_bindings(payload))

        "place" in changes ->
          localize.("«%{event}» has a new place.", event_bindings(payload))

        true ->
          localize.("«%{event}» moved to %{when}.", event_bindings(payload))
      end

    %{title: localize.("Event changed", %{}), body: body, url: payload["url"] || "/"}
  end

  def build("community_event_reminder", payload, localize) do
    %{
      title: localize.("Starting soon", %{}),
      body: localize.("«%{event}» starts in two hours (%{when}).", event_bindings(payload)),
      url: payload["url"] || "/"
    }
  end

  def build("community_event_guest_joined", payload, localize) do
    %{
      title: localize.("Your guest is coming", %{}),
      body:
        localize.(
          "%{nickname} is coming to «%{event}» with your guest pass.",
          Map.put(event_bindings(payload), :nickname, payload["person_nickname"])
        ),
      url: payload["url"] || "/"
    }
  end

  def build("community_event_trial_offer", payload, localize) do
    %{
      title: localize.("Try a class", %{}),
      body:
        localize.(
          "Liked «%{event}»? %{box} invites you to a trial class.",
          Map.put(event_bindings(payload), :box, payload["box_name"])
        ),
      url: payload["url"] || "/"
    }
  end

  def build("community_event_message", payload, localize) do
    %{
      title: localize.("Message about «%{event}»", event_bindings(payload)),
      body: payload["message"] || "",
      url: payload["url"] || "/"
    }
  end

  def build("around_new_matches", payload, localize) do
    %{
      title: localize.("New near you", %{}),
      body:
        localize.("New for «%{name}»: %{count}", %{
          name: payload["filter_name"],
          count: payload["count"]
        }),
      url: payload["url"] || "/around"
    }
  end

  # ADR-158: neutral wording, no numbers.
  def build("body_measure_reminder", payload, localize) do
    %{
      title: localize.("Time for a new measurement", %{}),
      body: localize.("A new snapshot helps you see your trend. It takes a minute.", %{}),
      url: payload["url"] || "/journal"
    }
  end

  # ADR-155 (board 10, Q3).
  def build("check_in_visitor", payload, localize) do
    bindings = %{
      nickname: payload["person_nickname"],
      box: payload["box_name"],
      when: payload["scanned_when"] || payload["scanned_at"]
    }

    body =
      if payload["trial_available"] in [true, "true"],
        do:
          localize.(
            "%{nickname} scanned the door at %{box} (%{when}) - not a member yet. Trials are open.",
            bindings
          ),
        else:
          localize.(
            "%{nickname} scanned the door at %{box} (%{when}) - not a member yet.",
            bindings
          )

    %{
      title: localize.("Visitor at the door", %{}),
      body: body,
      url: payload["url"] || "/admin/check-in"
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

  def build("booking_waitlist_promoted", payload, localize) do
    %{
      title: localize.("You got a spot", %{}),
      body:
        localize.(
          "A place opened up in %{class}. Your booking is confirmed or awaiting approval.",
          %{
            class: payload["class_name"] || ""
          }
        ),
      url: payload["url"] || "/schedule"
    }
  end

  def build("package_expiring", payload, localize) do
    %{
      title: localize.("Your package ends soon", %{}),
      body:
        localize.("%{package} ends on %{date}.", %{
          package: payload["package_name"] || "",
          date: payload["ends_on"] || ""
        }),
      url: payload["url"] || "/account/billing"
    }
  end

  def build("subscription_expiring", payload, localize) do
    params = %{
      package: payload["package_name"] || localize.("your subscription", %{}),
      date: payload["ends_on"] || "",
      days: payload["days_left"] || 0
    }

    %{
      title: localize.("Your subscription ends soon", %{}),
      body:
        payload["body"] ||
          localize.(
            "%{package} ends on %{date} (in %{days} days). Renew to keep booking classes.",
            params
          ),
      url: payload["url"] || "/account/billing"
    }
  end

  def build("form_review_submitted", payload, localize) do
    %{
      title: localize.("New form review request", %{}),
      body:
        localize.("%{client} sent a video for feedback.", %{
          client: payload["client_nickname"] || ""
        }),
      url: payload["url"] || "/admin/coaching?tab=form-reviews"
    }
  end

  def build("form_review_completed", payload, localize) do
    %{
      title: localize.("Your form review is ready", %{}),
      body: localize.("Your coach left feedback on your video.", %{}),
      url: payload["url"] || "/coaching"
    }
  end

  def build("coaching_reply_overdue", payload, localize) do
    %{
      title: localize.("A client is waiting for a reply", %{}),
      body:
        localize.("%{client} has been waiting longer than the promised reply time.", %{
          client: payload["client_nickname"] || ""
        }),
      url: payload["url"] || "/admin/coaching?tab=replies"
    }
  end

  def build("nutrition_plan_updated", payload, localize) do
    %{
      title: localize.("Your nutrition plan was updated", %{}),
      body: localize.("Open it to see what changed.", %{}),
      url: payload["url"] || "/coaching"
    }
  end

  def build("appointment_booked", payload, localize) do
    %{
      title: localize.("New appointment booked", %{}),
      body:
        localize.("%{client} booked a session for %{time}.", %{
          client: payload["client_nickname"] || "",
          time: payload["starts_at"] || ""
        }),
      url: payload["url"] || "/admin/appointments"
    }
  end

  def build("appointment_cancelled", payload, localize) do
    %{
      title: localize.("Appointment cancelled", %{}),
      body:
        localize.("The session on %{time} was cancelled.", %{time: payload["starts_at"] || ""}),
      url: payload["url"] || "/appointments"
    }
  end

  def build("coach_client_assigned", payload, localize) do
    %{
      title: localize.("A coach took a new athlete", %{}),
      body:
        localize.("%{coach} is now coaching %{client}.", %{
          coach: payload["coach_nickname"] || "",
          client: payload["client_nickname"] || ""
        }),
      url: payload["url"] || "/admin/users"
    }
  end

  def build("inventory_repair_needed", payload, localize) do
    %{
      title: localize.("A machine needs attention", %{}),
      body:
        localize.("%{machine}: %{note}", %{
          machine: payload["machine_name"] || "",
          note: payload["body"] || ""
        }),
      url: payload["url"] || "/admin/inventory"
    }
  end

  def build("inventory_stock_low", %{"status" => "reported"} = payload, localize) do
    %{
      title: localize.("Reported running low", %{}),
      body:
        localize.("%{item}: %{note}", %{
          item: payload["supply_name"] || "",
          note: payload["note"] || ""
        }),
      url: payload["url"] || "/admin/inventory"
    }
  end

  def build("inventory_digest", payload, localize) do
    %{
      title: localize.("Inventory today", %{}),
      body:
        localize.("Needs attention: %{items}", %{
          items: Enum.join(List.wrap(payload["highlights"]), ", ")
        }),
      url: payload["url"] || "/admin/inventory"
    }
  end

  def build("inventory_stock_low", payload, localize) do
    %{
      title: localize.("Running low", %{}),
      body:
        localize.("%{item}: %{quantity} left.", %{
          item: payload["supply_name"] || "",
          quantity: payload["quantity"] || ""
        }),
      url: payload["url"] || "/admin/inventory"
    }
  end

  def build("coach_note_viewed", payload, localize) do
    %{
      title: localize.("An admin read your note", %{}),
      body:
        localize.("%{reader} read your note about %{client} at %{time}.", %{
          reader: payload["reader_nickname"] || "",
          client: payload["client_nickname"] || "",
          time: payload["read_at"] || ""
        }),
      url: payload["url"] || "/admin/users"
    }
  end

  def build("subscription_grace", payload, localize) do
    params = %{
      package: payload["package_name"] || localize.("your subscription", %{}),
      date: payload["grace_until"] || ""
    }

    %{
      title: localize.("Your subscription has ended", %{}),
      body:
        payload["body"] ||
          localize.(
            "%{package} has ended. You keep access until %{date}; renew before then to keep booking classes.",
            params
          ),
      url: payload["url"] || "/account/billing"
    }
  end

  def build("access_ended", payload, localize) do
    body =
      if payload["reason"] == "overdue_payment",
        do:
          localize.(
            "Your access is paused because a payment is overdue. Pay the outstanding balance to book classes again.",
            %{}
          ),
        else:
          localize.("Your access has ended. Renew your subscription to book classes again.", %{})

    cancelled = payload["cancelled_bookings"] || 0

    body =
      if cancelled > 0,
        do:
          body <>
            " " <>
            localize.("Your upcoming bookings were cancelled: %{count}.", %{count: cancelled}),
        else: body

    %{
      title: localize.("Your access has ended", %{}),
      body: payload["body"] || body,
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
      title: localize.("TrainingJournal", %{}),
      body: payload["body"] || localize.("You have a new notification.", %{}),
      url: payload["url"] || "/"
    }
  end

  defp event_bindings(payload),
    do: %{
      event: payload["event_title"],
      when: payload["event_when"] || payload["event_starts_at"]
    }

  defp admin_url(path, payload),
    do: AdminPath.admin_url(path, payload["organization_slug"])

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
