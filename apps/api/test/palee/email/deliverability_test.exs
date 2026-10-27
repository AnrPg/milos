defmodule Palee.Email.DeliverabilityTest do
  # ADR-212: provider events, suppression state, one-click unsubscribe,
  # retention and the budget stats.
  use Palee.DataCase, async: false

  import Palee.EmailCase
  import Swoosh.TestAssertions

  alias Palee.Email
  alias Palee.Email.{LinkToken, Message, ProviderEvent}
  alias Palee.Repo

  @assigns %{name: "Jo", url: "https://palee.app/x"}

  defp sent_message(to \\ "jo@box.test", opts \\ []) do
    {:ok, message} = Email.enqueue(Keyword.get(opts, :kind, :sample_notice), to, @assigns, opts)
    assert deliver_enqueued_emails() >= 1
    Repo.get!(Message, message.id)
  end

  defp event(name, message, extra \\ %{}) do
    Map.merge(
      %{
        "event" => name,
        "email" => message.to_address,
        "id" => 1,
        "message-id" => message.message_id,
        "ts_event" => 1_767_225_600,
        "ts_epoch" => 1_767_225_600_000
      },
      extra
    )
  end

  describe "provider events" do
    test "a hard bounce suppresses the address and marks the message bounced" do
      message = sent_message()

      assert {:ok, %{applied: 1, duplicate: 0, unmatched: 0}} =
               Email.handle_provider_events(
                 :brevo,
                 event("hard_bounce", message, %{"reason" => "550 unknown"})
               )

      assert Repo.get!(Message, message.id).status == "bounced"
      assert Email.suppressed?("jo@box.test")
      refute Email.deliverable?("Jo@Box.test")
      assert %{reason: "bounce", since: %DateTime{}} = Email.suppression("jo@box.test")
      assert {:error, :suppressed} = Email.enqueue(:sample_notice, "jo@box.test", @assigns)

      assert [%ProviderEvent{event: "hard_bounce", reason: "550 unknown"}] =
               Email.message_store().provider_events(message.id)
    end

    test "invalid and blocked addresses bounce; a complaint suppresses as a complaint" do
      for {name, status, reason} <- [
            {"invalid_email", "bounced", "bounce"},
            {"blocked", "bounced", "bounce"},
            {"spam", "complained", "complaint"}
          ] do
        to = "#{name}@box.test"
        message = sent_message(to)

        assert {:ok, %{applied: 1}} = Email.handle_provider_events(:brevo, event(name, message))
        assert Repo.get!(Message, message.id).status == status
        assert Email.suppression(to).reason == reason
      end
    end

    test "a soft bounce is only recorded" do
      message = sent_message()

      assert {:ok, %{applied: 1}} =
               Email.handle_provider_events(:brevo, event("soft_bounce", message))

      assert Repo.get!(Message, message.id).status == "sent"
      assert Email.deliverable?("jo@box.test")

      assert [%ProviderEvent{event: "soft_bounce"}] =
               Email.message_store().provider_events(message.id)
    end

    test "a delivery sets delivered_at once" do
      message = sent_message()

      assert {:ok, %{applied: 1}} =
               Email.handle_provider_events(:brevo, event("delivered", message))

      assert %{status: "sent", delivered_at: ~U[2026-01-01 00:00:00.000000Z]} =
               Repo.get!(Message, message.id)

      assert {:ok, %{delivered_at: ~U[2026-01-01 00:00:00.000000Z]}} = Email.status(message.id)
    end

    test "an unsubscribe opts the address out of that transactional kind" do
      message = sent_message()

      assert {:ok, %{applied: 1}} =
               Email.handle_provider_events(:brevo, event("unsubscribed", message))

      assert Email.opted_out?("jo@box.test", :sample_notice)
      assert Email.deliverable?("jo@box.test")
      assert {:error, :suppressed} = Email.enqueue(:sample_notice, "jo@box.test", @assigns)
    end

    test "the same event twice is applied once, even after the address was unsuppressed" do
      message = sent_message()
      payload = event("hard_bounce", message)

      assert {:ok, %{applied: 1}} = Email.handle_provider_events(:brevo, payload)
      :ok = Email.unsuppress("jo@box.test")

      assert {:ok, %{applied: 0, duplicate: 1}} = Email.handle_provider_events(:brevo, payload)
      refute Email.suppressed?("jo@box.test")
      assert length(Email.message_store().provider_events(message.id)) == 1
    end

    test "without a known Message-ID the newest message to the address is matched" do
      message = sent_message()

      payload = event("hard_bounce", message, %{"message-id" => "<unknown@relay.brevo>"})
      assert {:ok, %{applied: 1}} = Email.handle_provider_events(:brevo, payload)
      assert Repo.get!(Message, message.id).status == "bounced"

      # An address Palee never mailed is still suppressed.
      stranger = %{"event" => "hard_bounce", "email" => "who@else.test", "ts_epoch" => 1}
      assert {:ok, %{applied: 1}} = Email.handle_provider_events(:brevo, stranger)
      assert Email.suppressed?("who@else.test")

      # Neither an address nor a known message: nothing to act on.
      assert {:ok, %{unmatched: 1}} =
               Email.handle_provider_events(:brevo, %{
                 "event" => "hard_bounce",
                 "message-id" => "<x@y>"
               })
    end

    test "a batch is applied event by event, and a non-event is refused" do
      a = sent_message("a@box.test")
      b = sent_message("b@box.test")

      assert {:ok, %{applied: 2}} =
               Email.handle_provider_events(:brevo, [
                 event("hard_bounce", a),
                 event("delivered", b)
               ])

      assert {:error, :invalid_payload} = Email.handle_provider_events(:brevo, %{"nope" => 1})
    end
  end

  test "undeliverable/1 lists the suppressed addresses of a list in one query" do
    {:ok, _} = Email.suppress("gone@box.test", :bounce)

    assert Email.undeliverable([" Gone@Box.test", "ok@box.test", nil]) ==
             MapSet.new(["gone@box.test"])

    assert Email.undeliverable([]) == MapSet.new()
    refute Email.deliverable?("not an address")
  end

  describe "one-click unsubscribe" do
    test "transactional mail carries List-Unsubscribe headers and a footer link" do
      {:ok, _message} = Email.enqueue(:sample_notice, "jo@box.test", @assigns, locale: "el")

      found = assert_email_enqueued(kind: :sample_notice)
      assert found.html =~ "/api/email/unsubscribe/"
      assert found.html =~ "Διακοπή αυτών των email"
      refute found.html =~ "<!--palee:unsubscribe-->"

      assert found.text =~
               ~r{Διακοπή αυτών των email: http://localhost:4000/api/email/unsubscribe/[A-Za-z0-9_-]+\n\z}

      assert deliver_enqueued_emails() == 1

      assert_email_sent(fn email ->
        assert email.headers["List-Unsubscribe"] =~
                 ~r{\A<http://localhost:4000/api/email/unsubscribe/[A-Za-z0-9_-]+>\z}

        assert email.headers["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"
      end)
    end

    test "security and account mail never carries one" do
      {:ok, _message} =
        Email.enqueue(:sample_notice, "jo@box.test", @assigns, category: :security)

      found = assert_email_enqueued(kind: :sample_notice)
      refute found.html =~ "unsubscribe"
      refute found.text =~ "unsubscribe"
      assert deliver_enqueued_emails() == 1

      assert_email_sent(fn email -> not Map.has_key?(email.headers, "List-Unsubscribe") end)
    end

    test "the signed link opts the address out of that kind only" do
      url = Email.unsubscribe_url("Jo@Box.test", :sample_notice, "de")
      token = url |> String.split("/") |> List.last()

      assert {:ok, %{kind: "sample_notice", locale: "de"}} = Email.unsubscribe_info(token)
      refute Email.opted_out?("jo@box.test", :sample_notice)

      assert {:ok, %{kind: "sample_notice"}} = Email.unsubscribe(token)
      assert {:ok, _again} = Email.unsubscribe(token)
      assert Email.opted_out?("jo@box.test", :sample_notice)
      refute Email.opted_out?("jo@box.test", :corporate_invoice_issued)
      refute Email.suppressed?("jo@box.test")

      assert {:error, :suppressed} = Email.enqueue(:sample_notice, "jo@box.test", @assigns)

      # Security mail still goes.
      assert {:ok, _security} =
               Email.enqueue(:sample_notice, "jo@box.test", @assigns, category: :security)

      assert {:error, :invalid} = Email.unsubscribe(token <> "x")
    end

    test "an opt-out after enqueue stops the queued email" do
      {:ok, message} = Email.enqueue(:sample_notice, "jo@box.test", @assigns)

      token =
        Email.unsubscribe_url("jo@box.test", :sample_notice, "en")
        |> String.split("/")
        |> List.last()

      {:ok, _} = Email.unsubscribe(token)

      assert deliver_enqueued_emails() == 0
      assert {:ok, %{status: "suppressed"}} = Email.status(message.id)
      assert_no_email_sent()
    end
  end

  describe "retention" do
    test "purges messages older than 90 days, never ones still waiting, and spent link tokens after 7 days" do
      now = DateTime.utc_now()
      old = DateTime.add(now, -91, :day)

      sent = sent_message()
      fresh = sent_message("fresh@box.test")
      {:ok, waiting} = Email.enqueue(:sample_notice, "wait@box.test", @assigns)
      {:ok, %{applied: 1}} = Email.handle_provider_events(:brevo, event("delivered", sent))

      Repo.update_all(Message |> where([m], m.id in ^[sent.id, waiting.id]),
        set: [inserted_at: old]
      )

      login = Palee.TestFixtures.user_fixture()
      login_id = login.login_id

      {:ok, _raw, used} = Palee.Email.LinkTokens.issue(:verify_email, login_id, now: now)

      {:ok, _raw, expired} =
        Palee.Email.LinkTokens.issue(:email_change_revert, login_id, now: now)

      {:ok, _raw, live} = Palee.Email.LinkTokens.issue(:email_change_revert, login_id, now: now)

      Repo.update_all(LinkToken |> where([t], t.id == ^used.id),
        set: [used_at: DateTime.add(now, -8, :day)]
      )

      Repo.update_all(LinkToken |> where([t], t.id == ^expired.id),
        set: [expires_at: DateTime.add(now, -8, :day)]
      )

      assert %{messages: 1, link_tokens: 2} = Email.purge(now)

      refute Repo.get(Message, sent.id)
      assert Repo.get(Message, waiting.id)
      assert Repo.get(Message, fresh.id)
      assert Email.message_store().provider_events(sent.id) == []
      assert Repo.get(LinkToken, live.id)
      refute Repo.get(LinkToken, used.id)
      refute Repo.get(LinkToken, expired.id)
    end
  end

  test "sending_stats/1 counts today's sent mail and the deferred backlog" do
    sent_message()
    sent_message("two@box.test")
    {:ok, waiting} = Email.enqueue(:sample_notice, "later@box.test", @assigns)
    Repo.update_all(Message |> where([m], m.id == ^waiting.id), set: [status: "deferred"])

    assert %{sent_today: 2, deferred: 1, daily_budget: 100_000, hard_cap: 100_000} =
             Email.sending_stats()
  end

  test "the email that crosses 80% of the budget logs one warning" do
    previous = Application.get_env(:palee, :email_budget)
    Application.put_env(:palee, :email_budget, daily_budget: 5, hard_cap: 6)
    on_exit(fn -> Application.put_env(:palee, :email_budget, previous) end)

    for n <- 1..3, do: sent_message("n#{n}@box.test")

    log = ExUnit.CaptureLog.capture_log(fn -> sent_message("n4@box.test") end)
    assert log =~ "email_budget_warning sent_today=4 daily_budget=5 hard_cap=6"
    refute log =~ "@box.test"

    refute ExUnit.CaptureLog.capture_log(fn -> sent_message("n5@box.test") end) =~
             "email_budget_warning"
  end
end
