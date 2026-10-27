defmodule Palee.MailerTest do
  # Swaps the global :mail_from config.
  use ExUnit.Case, async: false

  import Swoosh.TestAssertions

  alias Palee.Finance.Emails.CorporateInvoiceEmail
  alias Palee.Localization
  alias Palee.Mailer
  alias Swoosh.Adapters.SMTP.Helpers

  @from {"Palee", "no-reply@palee.app"}

  setup do
    previous = Application.fetch_env!(:palee, :mail_from)

    Application.put_env(:palee, :mail_from,
      name: "Palee",
      address: "no-reply@palee.app",
      reply_to: "support@palee.app"
    )

    on_exit(fn -> Application.put_env(:palee, :mail_from, previous) end)
  end

  defp emails do
    invoice = %{
      invoice_number: "INV-1",
      period_start: ~D[2026-11-01],
      period_end: ~D[2026-11-30],
      due_on: ~D[2026-11-15],
      seats_billed: 1,
      unit_price_cents: 2_000,
      total_cents: 2_000
    }

    client = %{company_name: "Acme", contact_name: nil, billing_email: "ap@acme.test"}
    localize = &Localization.translate("en", &1, &2, "corporate_invoices")

    [
      CorporateInvoiceEmail.build(
        :issued,
        %{invoice: invoice, client: client, gym_name: "Gym", from: @from},
        localize
      ),
      CorporateInvoiceEmail.build(
        :reminder,
        %{invoice: invoice, client: client, gym_name: "Gym", from: @from},
        localize
      )
    ]
  end

  test "every email goes out with a Message-ID on the sender's domain and no infrastructure names" do
    {:ok, hostname} = :inet.gethostname()

    for email <- emails() do
      assert {:ok, _} = Mailer.deliver(email)
      assert_email_sent(fn sent -> assert sent.subject == email.subject end)

      stamped = Mailer.stamp(email)
      assert stamped.headers["Message-ID"] =~ ~r/\A<[0-9a-f-]{36}@palee\.app>\z/

      rendered = Helpers.body(stamped, [])
      assert rendered =~ "Message-ID: #{stamped.headers["Message-ID"]}"
      assert rendered =~ "From: Palee <no-reply@palee.app>"
      assert rendered =~ "Reply-To: Palee <support@palee.app>"
      refute rendered =~ ~r/milos/i
      refute rendered =~ "4kq.net"
      refute rendered =~ List.to_string(hostname)
    end
  end

  test "an existing Message-ID is kept" do
    email = Swoosh.Email.new(from: @from) |> Swoosh.Email.header("Message-ID", "<a@b.c>")
    assert Mailer.stamp(email).headers["Message-ID"] == "<a@b.c>"
  end

  test "the default sender address never uses an internal host" do
    assert Mailer.default_from_address("palee.app") == "no-reply@palee.app"

    for host <- ~w(milos.4kq.net 4kq.net example.com localhost palee-api palee-api.tenant-m4.svc) do
      assert_raise RuntimeError, ~r/MAIL_FROM_ADDRESS is missing/, fn ->
        Mailer.default_from_address(host)
      end
    end
  end
end
