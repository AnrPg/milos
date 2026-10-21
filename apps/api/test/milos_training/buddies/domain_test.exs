defmodule MilosTraining.Buddies.DomainTest do
  @moduledoc "ADR-160: the pure rules of Buddy για στήριξη."

  use ExUnit.Case, async: true

  alias MilosTraining.Buddies.Domain.{
    Eligibility,
    InviteToken,
    LinkPolicy,
    MessagePolicy,
    QuietHours,
    SettingsPolicy,
    SummarySharingPolicy,
    SupportPolicy,
    WeeklySummary
  }

  @now ~U[2026-10-20 18:00:00.000000Z]

  defp link(attrs) do
    Map.merge(
      %{
        id: "l1",
        user_id: "me",
        buddy_user_id: "dimitra",
        status: "pending",
        expires_at: LinkPolicy.expires_at(@now),
        started_at: nil,
        ended_at: nil,
        ended_by_id: nil
      },
      attrs
    )
  end

  describe "link state machine" do
    test "an invite waits for the buddy to accept, then becomes active" do
      pending = link(%{})

      assert {:ok, %{status: "active", started_at: @now}} =
               LinkPolicy.transition(pending, :accept, :buddy, @now)

      assert {:error, :forbidden} = LinkPolicy.transition(pending, :accept, :requester, @now)
      assert {:ok, %{status: "declined"}} = LinkPolicy.transition(pending, :decline, :buddy, @now)
    end

    test "either side leaves at any time; who ended it is kept" do
      active = link(%{status: "active", started_at: @now})

      assert {:ok, %{status: "ended", ended_by_id: "dimitra"}} =
               LinkPolicy.transition(active, :leave, :buddy, @now)

      assert {:ok, %{status: "ended", ended_by_id: "me"}} =
               LinkPolicy.transition(active, :leave, :requester, @now)

      assert {:ok, %{status: "ended"}} = LinkPolicy.transition(active, :block, :buddy, @now)
      assert {:error, :not_found} = LinkPolicy.transition(active, :leave, nil, @now)
    end

    test "a requester can withdraw a pending invite; closed links stay closed" do
      assert {:ok, %{status: "ended"}} =
               LinkPolicy.transition(link(%{}), :leave, :requester, @now)

      assert {:error, :buddy_link_closed} =
               LinkPolicy.transition(link(%{status: "ended"}), :accept, :buddy, @now)

      assert {:error, :buddy_link_closed} =
               LinkPolicy.transition(link(%{status: "declined"}), :leave, :buddy, @now)
    end

    test "an invite expires after seven days" do
      sent = link(%{expires_at: LinkPolicy.expires_at(@now)})
      later = DateTime.add(@now, 7 * 86_400, :second)

      assert LinkPolicy.effective_status(sent, DateTime.add(later, -1, :second)) == "pending"
      assert LinkPolicy.effective_status(sent, later) == "expired"
      assert {:error, :buddy_invite_expired} = LinkPolicy.transition(sent, :accept, :buddy, later)
    end

    test "only invites and acceptances notify; leaving is quiet" do
      assert LinkPolicy.notifies?(:invite)
      assert LinkPolicy.notifies?(:accept)
      refute LinkPolicy.notifies?(:leave)
      refute LinkPolicy.notifies?(:decline)
      refute LinkPolicy.notifies?(:block)
    end

    test "roles and the other party" do
      l = link(%{})
      assert LinkPolicy.role(l, "me") == :requester
      assert LinkPolicy.role(l, "dimitra") == :buddy
      assert LinkPolicy.role(l, "stranger") == nil
      assert LinkPolicy.other(l, "me") == "dimitra"
      assert LinkPolicy.other(l, "dimitra") == "me"
      assert LinkPolicy.role(link(%{buddy_user_id: nil}), nil) == nil
    end

    test "at most two open invites or buddies; expired and ended ones do not count" do
      active = link(%{status: "active"})
      pending = link(%{})
      expired = link(%{expires_at: DateTime.add(@now, -1, :second)})
      ended = link(%{status: "ended"})

      assert :ok = LinkPolicy.check_limit([active, expired, ended], @now)
      assert {:error, :buddy_limit_reached} = LinkPolicy.check_limit([active, pending], @now)
    end

    test "only the requester chooses the weekly summary, on an open link" do
      active = link(%{status: "active"})
      assert LinkPolicy.can_set_summary?(active, "me", @now)
      refute LinkPolicy.can_set_summary?(active, "dimitra", @now)
      refute LinkPolicy.can_set_summary?(link(%{status: "ended"}), "me", @now)
    end
  end

  describe "eligibility" do
    test "coach, club in common or follow; never yourself or a stranger" do
      for relation <- ~w(coach club follow),
          do: assert(:ok = Eligibility.check("a", "b", relation))

      assert {:error, :not_eligible_for_buddy} = Eligibility.check("a", "b", nil)
      assert {:error, :cannot_buddy_self} = Eligibility.check("a", "a", "club")
      assert {:error, :not_found} = Eligibility.check("a", nil, nil)
    end

    test "short search terms do not widen the search" do
      assert Eligibility.search_term("k") == nil
      assert Eligibility.search_term("  ko ") == "ko"
      assert Eligibility.search_term(nil) == nil
    end
  end

  describe "support requests" do
    test "the message is optional and at most 280 characters" do
      assert {:ok, nil} = SupportPolicy.normalize_message(nil)
      assert {:ok, nil} = SupportPolicy.normalize_message("   ")
      assert {:ok, "Δύσκολο βράδυ."} = SupportPolicy.normalize_message(" Δύσκολο βράδυ. ")
      assert {:ok, _} = SupportPolicy.normalize_message(String.duplicate("α", 280))

      assert {:error, :message_too_long} =
               SupportPolicy.normalize_message(String.duplicate("α", 281))
    end

    test "sources are craving or quick" do
      assert {:ok, "craving"} = SupportPolicy.normalize_source(:craving)
      assert {:ok, "quick"} = SupportPolicy.normalize_source(nil)
      assert {:error, :invalid_support_source} = SupportPolicy.normalize_source("diet")
    end

    test "three requests an hour at most" do
      assert :ok = SupportPolicy.check_rate(2)
      assert {:error, :support_rate_limited} = SupportPolicy.check_rate(3)
      assert SupportPolicy.rate_window_start(@now) == DateTime.add(@now, -3600, :second)
      assert {:error, :no_active_buddies} = SupportPolicy.check_buddies([])
    end

    test "undo within five seconds, before buddies are told" do
      request = %{inserted_at: @now, undone_at: nil, delivered_at: nil}
      assert :ok = SupportPolicy.can_undo?(request, DateTime.add(@now, 5, :second))

      assert {:error, :undo_window_passed} =
               SupportPolicy.can_undo?(request, DateTime.add(@now, 6, :second))

      assert {:error, :undo_window_passed} =
               SupportPolicy.can_undo?(%{request | delivered_at: @now}, @now)

      assert {:error, :already_undone} =
               SupportPolicy.can_undo?(%{request | undone_at: @now}, @now)

      assert SupportPolicy.deliver_at(request) == DateTime.add(@now, 5, :second)
      assert SupportPolicy.deliverable?(request)
      refute SupportPolicy.deliverable?(%{request | undone_at: @now})
    end

    test "the calm card is due after ten minutes with no reply, gone once someone answers" do
      request = %{inserted_at: @now, undone_at: nil, delivered_at: @now, nudge_sent_at: nil}
      before = DateTime.add(@now, 599, :second)
      after_ten = DateTime.add(@now, 600, :second)

      refute SupportPolicy.nudge(request, [], before).due
      card = SupportPolicy.nudge(request, [], after_ten)
      assert card.due and card.can_resend
      assert card.suggestions == ~w(breathing water walk)
      assert card.help_lines.informational
      refute SupportPolicy.nudge(request, [%{kind: "here"}], after_ten).due
      assert SupportPolicy.nudge_needed?(request, [], after_ten)
      refute SupportPolicy.nudge_needed?(%{request | nudge_sent_at: @now}, [], after_ten)
      refute SupportPolicy.nudge_needed?(%{request | undone_at: @now}, [], after_ten)
      refute SupportPolicy.nudge_needed?(%{request | delivered_at: nil}, [], after_ten)
    end

    test "replies: quick kinds or words; call carries the phone only when shared" do
      assert {:ok, "here", nil} = SupportPolicy.validate_reply("here", nil)
      assert {:ok, "walk", "στις 10;"} = SupportPolicy.validate_reply("walk", " στις 10; ")
      assert {:error, :reply_text_required} = SupportPolicy.validate_reply("text", "  ")
      assert {:error, :invalid_reply_kind} = SupportPolicy.validate_reply("hug", nil)
      assert SupportPolicy.phone_for("call", "+30 690 000 0000") == "+30 690 000 0000"
      assert SupportPolicy.phone_for("call", nil) == nil
      assert SupportPolicy.phone_for("here", "+30 690 000 0000") == nil
    end
  end

  describe "quiet hours" do
    test "windows across midnight and within a day, in the buddy's zone" do
      from = ~T[23:00:00]
      to = ~T[07:00:00]
      # 18:00 UTC is 21:00 in Athens (EEST, +3).
      refute QuietHours.quiet?(from, to, "Europe/Athens", @now)
      assert QuietHours.quiet?(from, to, "Europe/Athens", ~U[2026-10-20 21:30:00Z])
      assert QuietHours.quiet?(from, to, "Europe/Athens", ~U[2026-10-21 03:59:00Z])
      refute QuietHours.quiet?(from, to, "Europe/Athens", ~U[2026-10-21 04:00:00Z])
      assert QuietHours.quiet?(~T[13:00:00], ~T[15:00:00], "Etc/UTC", ~U[2026-10-20 14:00:00Z])
      refute QuietHours.quiet?(nil, nil, "Etc/UTC", @now)
    end

    test "inside quiet hours a request is delivered silently" do
      hours = %{quiet_from: ~T[20:00:00], quiet_to: ~T[22:00:00], tz: "Europe/Athens"}
      assert %{silent: true} = QuietHours.delivery(hours, @now)
      assert %{silent: false} = QuietHours.delivery(nil, @now)
    end
  end

  describe "settings" do
    defp valid_zone?(zone), do: zone in ["Europe/Athens", "Etc/UTC"]

    test "quiet hours, zone and phone sharing (off by default)" do
      assert SettingsPolicy.effective(nil).share_phone == false

      assert {:ok, %{quiet_from: ~T[23:00:00], quiet_to: ~T[07:00:00], tz: "Etc/UTC"}} =
               SettingsPolicy.changes(
                 nil,
                 %{"quiet_hours" => %{"from" => "23:00", "to" => "07:00"}, "tz" => "Etc/UTC"},
                 &valid_zone?/1
               )

      assert {:ok, %{quiet_from: nil}} =
               SettingsPolicy.changes(nil, %{"quiet_hours" => nil}, &valid_zone?/1)

      assert {:error, :invalid_quiet_hours} =
               SettingsPolicy.changes(
                 nil,
                 %{"quiet_hours" => %{"from" => "23:00", "to" => "23:00"}},
                 &valid_zone?/1
               )

      assert {:error, :unknown_time_zone} =
               SettingsPolicy.changes(nil, %{"tz" => "Mars/Base"}, &valid_zone?/1)

      assert {:error, :phone_required} =
               SettingsPolicy.changes(nil, %{"share_phone" => true}, &valid_zone?/1)

      assert {:ok, %{share_phone: true, phone: "+30 690 123 4567"}} =
               SettingsPolicy.changes(
                 nil,
                 %{share_phone: true, phone: "+30 690 123 4567"},
                 &valid_zone?/1
               )

      assert {:error, :invalid_phone} =
               SettingsPolicy.changes(nil, %{"phone" => "call me"}, &valid_zone?/1)
    end
  end

  describe "weekly summary" do
    test "Sunday 19:00 in the member's zone" do
      # 2026-10-25 is a Sunday; Athens is UTC+2 after the clocks change that day.
      assert WeeklySummary.due?("Europe/Athens", ~U[2026-10-25 17:00:00Z])
      refute WeeklySummary.due?("Europe/Athens", ~U[2026-10-25 16:00:00Z])
      refute WeeklySummary.due?("Europe/Athens", ~U[2026-10-24 17:00:00Z])
    end

    test "counts only; never times, causes, foods or notes" do
      cravings = [
        %{
          outcome: "resisted",
          triggers: ["stress"],
          intensity: 9,
          note: "pizza",
          occurred_at: @now
        },
        %{outcome: "ate_off_plan", triggers: ["social"], intensity: 6, note: nil},
        %{outcome: nil}
      ]

      summary =
        WeeklySummary.compose(WeeklySummary.week("Europe/Athens", @now), cravings, 2)

      assert summary == %{
               week_start: ~D[2026-10-19],
               week_end: ~D[2026-10-25],
               hard_moments: 3,
               overcome: 1,
               support_requests: 2
             }

      flat = inspect(summary)
      for leak <- ["stress", "social", "pizza", "intensity", "occurred"], do: refute(flat =~ leak)
    end

    test "one summary per buddy and week" do
      assert WeeklySummary.dedupe_key("l1", ~D[2026-10-19]) ==
               "buddy_weekly_summary:l1:2026-10-19"

      assert WeeklySummary.previous_week("Europe/Athens", @now) ==
               {~D[2026-10-12], ~D[2026-10-18]}
    end
  end

  describe "coach summary sharing" do
    defp grant(scope, withdrawn \\ nil),
      do: %{scope: scope, granted_at: @now, withdrawn_at: withdrawn}

    test "toggles come from active grants; cravings need the summary" do
      assert %{wellness: false, cravings: false} = SummarySharingPolicy.toggles([])

      assert %{wellness: true, cravings: true} =
               SummarySharingPolicy.toggles([grant("wellness"), grant("cravings")])

      assert %{wellness: false, cravings: false} =
               SummarySharingPolicy.toggles([grant("cravings"), grant("wellness", @now)])
    end

    test "changes: grant and withdraw; turning the summary off withdraws both" do
      off = SummarySharingPolicy.toggles([])
      on = SummarySharingPolicy.toggles([grant("wellness"), grant("cravings")])

      assert {:ok, %{grant: ["wellness"], withdraw: []}} =
               SummarySharingPolicy.changes(off, %{"wellness" => true})

      assert {:error, :summary_required} =
               SummarySharingPolicy.changes(off, %{"cravings" => true})

      assert {:ok, %{grant: [], withdraw: withdraw}} =
               SummarySharingPolicy.changes(on, %{wellness: false})

      assert Enum.sort(withdraw) == ["cravings", "wellness"]

      assert {:error, :invalid_summary_sharing} =
               SummarySharingPolicy.changes(off, %{"wellness" => "yes"})
    end

    test "the coach sees counts, and craving times only with the second toggle" do
      week = %{
        nights_on_goal: 4,
        nights_logged: 6,
        water_days_on_goal: 5,
        water_days_logged: 7,
        meal_days_logged: 7,
        cravings: 2
      }

      cravings = [
        %{
          occurred_on: ~D[2026-10-14],
          occurred_at: ~U[2026-10-14 19:40:00Z],
          occurred_tz: "Europe/Athens",
          note: "chips",
          triggers: ["stress"],
          intensity: 8,
          outcome: "resisted"
        }
      ]

      only_wellness = SummarySharingPolicy.toggles([grant("wellness")])

      summary =
        SummarySharingPolicy.coach_summary(
          {~D[2026-10-12], ~D[2026-10-18]},
          only_wellness,
          week,
          cravings
        )

      assert summary.cravings == nil
      assert summary.sleep == %{nights_on_goal: 4, nights_logged: 6}

      both = SummarySharingPolicy.toggles([grant("wellness"), grant("cravings")])

      summary =
        SummarySharingPolicy.coach_summary({~D[2026-10-12], ~D[2026-10-18]}, both, week, cravings)

      assert summary.cravings == %{count: 1, moments: [%{date: ~D[2026-10-14], time: "22:40"}]}

      flat = inspect(summary)
      for leak <- ["chips", "stress", "intensity", "resisted"], do: refute(flat =~ leak)
    end
  end

  describe "buddy conversation" do
    test "bodies are trimmed, 1..2000 characters" do
      assert MessagePolicy.normalize_body("  γεια  ") == {:ok, "γεια"}
      assert MessagePolicy.normalize_body("   ") == {:error, :message_body_required}
      assert MessagePolicy.normalize_body(nil) == {:error, :message_body_required}
      assert {:ok, _} = MessagePolicy.normalize_body(String.duplicate("α", 2000))

      assert MessagePolicy.normalize_body(String.duplicate("α", 2001)) ==
               {:error, :message_too_long_body}
    end

    test "only the two people; writing only while active" do
      active = link(%{status: "active", started_at: @now, expires_at: nil})
      assert MessagePolicy.party?(active, "me")
      assert MessagePolicy.party?(active, "dimitra")
      refute MessagePolicy.party?(active, "kostas")
      refute MessagePolicy.party?(active, nil)

      assert MessagePolicy.can_post?(active, @now) == :ok
      refute MessagePolicy.read_only?(active, @now)

      for status <- ~w(ended declined expired pending) do
        closed = %{active | status: status}
        assert MessagePolicy.can_post?(closed, @now) == {:error, :buddy_link_read_only}
        assert MessagePolicy.read_only?(closed, @now)
      end
    end

    test "a support reply posts the quick reply, then the buddy's words" do
      assert MessagePolicy.reply_body("walk", "Shall we go for a walk?", nil) ==
               "Shall we go for a walk?"

      assert MessagePolicy.reply_body("call", "Call me", "Τώρα") == "Call me\n\nΤώρα"
      assert MessagePolicy.reply_body("text", "I'm here", "Μόνο λόγια") == "Μόνο λόγια"
    end

    test "cursor paging round-trips and refuses garbage" do
      row = %{inserted_at: @now, id: "6f1f2b38-8b7e-4f9b-9d9c-1d1c4c0a7a11"}
      cursor = MessagePolicy.encode_cursor(row)
      assert MessagePolicy.decode_cursor(cursor) == {:ok, row}
      assert MessagePolicy.decode_cursor(nil) == {:ok, nil}
      assert MessagePolicy.decode_cursor("nope") == {:error, :invalid_cursor}

      assert MessagePolicy.page_limit(nil) == 30
      assert MessagePolicy.page_limit("500") == 100
      assert MessagePolicy.page_limit(0) == 1

      assert {[^row], ^cursor} = MessagePolicy.page([row, %{row | id: "x"}], 1)
      assert {[^row], nil} = MessagePolicy.page([row], 1)
    end
  end

  test "invite tokens: only a digest is kept, malformed ones are refused" do
    token = InviteToken.generate()
    assert {:ok, digest} = InviteToken.decode(token)
    assert digest == InviteToken.digest(token)
    assert {:error, :not_found} = InviteToken.decode("short")
    assert {:error, :not_found} = InviteToken.decode(String.duplicate("$", 40))
    assert InviteToken.path(token) == "/buddy-invite/" <> token
  end
end
