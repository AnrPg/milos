defmodule Palee.Email.Domain.ProviderEventTest do
  use ExUnit.Case, async: true

  alias Palee.Email.Domain.ProviderEvent

  @bounce %{
    "event" => "hard_bounce",
    "email" => " Jo@Box.TEST ",
    "id" => 1234,
    "message-id" => "<abc@palee.app>",
    "ts_event" => 1_767_225_600,
    "ts_epoch" => 1_767_225_600_123,
    "reason" => "550 5.1.1 user unknown\r\nmore"
  }

  test "reads one Brevo event" do
    assert {:ok, [event]} = ProviderEvent.parse_brevo(@bounce)

    assert %{event: :hard_bounce, address: "jo@box.test", message_id: "<abc@palee.app>"} = event
    assert event.occurred_at == ~U[2026-01-01 00:00:00.123000Z]
    assert event.reason == "550 5.1.1 user unknown more"
    assert byte_size(event.digest) == 32
  end

  test "reads a batch, drops events Palee ignores, and wraps a bare Message-ID" do
    batch = [
      @bounce,
      %{"event" => "opened", "email" => "jo@box.test"},
      %{"event" => "delivered", "email" => "jo@box.test", "message-id" => "abc@palee.app"}
    ]

    assert {:ok, [%{event: :hard_bounce}, %{event: :delivered, message_id: "<abc@palee.app>"}]} =
             ProviderEvent.parse_brevo(batch)

    assert {:ok, [_one, _two]} = ProviderEvent.parse_brevo(%{"_json" => batch})
  end

  test "refuses what is not an event" do
    for payload <- [%{}, [], "x", [%{"email" => "jo@box.test"}], %{"event" => 1}] do
      assert {:error, :invalid_payload} = ProviderEvent.parse_brevo(payload)
    end
  end

  test "the same event has the same digest; another event, another digest" do
    {:ok, [a]} = ProviderEvent.parse_brevo(@bounce)
    {:ok, [b]} = ProviderEvent.parse_brevo(@bounce)
    {:ok, [c]} = ProviderEvent.parse_brevo(%{@bounce | "event" => "soft_bounce"})
    {:ok, [d]} = ProviderEvent.parse_brevo(%{@bounce | "ts_epoch" => 1_767_225_700_000})

    assert a.digest == b.digest
    refute a.digest == c.digest
    refute a.digest == d.digest
  end

  test "actions" do
    for event <- [:hard_bounce, :invalid_email, :blocked],
        do: assert(ProviderEvent.action(event) == {:suppress, :bounce, "bounced"})

    assert ProviderEvent.action(:spam) == {:suppress, :complaint, "complained"}
    assert {:ok, [%{event: :spam}]} = ProviderEvent.parse_brevo(%{"event" => "complaint"})
    assert ProviderEvent.action(:unsubscribed) == :opt_out
    assert ProviderEvent.action(:delivered) == :delivered

    for event <- [:soft_bounce, :deferred, :error],
        do: assert(ProviderEvent.action(event) == :record)
  end
end
