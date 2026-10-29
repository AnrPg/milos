defmodule PaleeWeb.AdminFiscalEmailControllerTest do
  @moduledoc """
  ADR-265 over HTTP: «Αποστολή με email» of a fiscal document. The PDF
  goes as an attachment through the outbox, in the document's language, to
  the buyer or a typed address; once per idempotency key; journaled; never
  from a demo business; staff without billing rights cannot send.
  """

  use PaleeWeb.ConnCase, async: false

  import Ecto.Query
  import Palee.EmailCase
  import Palee.TestFixtures

  alias Palee.{Fiscal, Organizations, Repo}

  @identity %{
    "legal_name" => "Κυψέλη Αθλητική ΙΚΕ",
    "trade_name" => "Κυψέλη Strong",
    "country_code" => "GR",
    "tax_id" => "090000045",
    "tax_office" => "Ζ' Αθηνών",
    "street" => "Φωκίωνος Νέγρη",
    "postal_code" => "11361",
    "city" => "Αθήνα"
  }

  setup %{conn: conn} do
    admin = admin_fixture(%{nickname: "mail_admin"})
    coach = user_fixture(%{nickname: "mail_coach"})

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Mail Fiscal #{System.unique_integer([:positive])}"
      })

    for {user, role} <- [{admin, :owner}, {coach, :coach}] do
      {:ok, _} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    {:ok, context} = Organizations.resolve_tenant_context(admin, organization.slug)
    base = "/api/org/#{organization.slug}/admin/fiscal"
    owner = put_bearer_token(conn, admin)

    owner
    |> put_req_header("content-type", "application/json")
    |> put("#{base}/identity", Jason.encode!(@identity))
    |> json_response(200)

    now = DateTime.utc_now()

    issue = fn key, buyer ->
      {:ok, document, :issued} =
        Fiscal.issue(
          context,
          %{
            kind: "receipt",
            issue_date: Organizations.local_date(context, now),
            idempotency_key: key,
            buyer: buyer,
            payment_method: "card",
            lines: [%{description: "Μηνιαία συνδρομή", quantity: 1, unit_price_cents: 6_000}]
          },
          admin.id,
          now
        )

      document
    end

    %{
      organization: organization,
      context: context,
      owner: owner,
      coach: put_bearer_token(conn, coach),
      base: base,
      with_buyer: issue.("mail-1", %{name: "Μαρία Κ.", email: "Maria@Example.test"}),
      retail: issue.("mail-2", nil)
    }
  end

  defp send_mail(conn, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(body))
  end

  test "sends the PDF to the buyer, once per key, and journals it", ctx do
    path = "#{ctx.base}/documents/#{ctx.with_buyer.id}/email"
    body = %{idempotency_key: "email-key-0001"}

    assert %{"email" => %{"recipient" => "buyer", "to" => "maria@example.test", "id" => id}} =
             ctx.owner |> send_mail(path, body) |> json_response(202)

    assert %{"email" => %{"id" => ^id}} =
             ctx.owner |> send_mail(path, body) |> json_response(200)

    email = assert_email_enqueued(kind: :fiscal_document, to: "maria@example.test")
    assert email.locale == "el"
    assert email.subject =~ ctx.with_buyer.number
    assert email.subject =~ "Κυψέλη Strong"
    assert email.text =~ "Σύνολο"
    assert email.html =~ "PDF"

    # The PDF travels with it.
    assert deliver_enqueued_emails() == 1

    Swoosh.TestAssertions.assert_email_sent(fn sent ->
      assert [%Swoosh.Attachment{filename: filename, content_type: "application/pdf", data: pdf}] =
               sent.attachments

      assert filename == "#{ctx.with_buyer.number}.pdf"
      assert String.starts_with?(pdf, "%PDF")
    end)

    # Journaled once, with a digest of the address, never the address.
    entries =
      Repo.all(
        from(e in "fiscal_journal_entries",
          where:
            e.organization_id == type(^ctx.organization.id, :binary_id) and
              e.event_type == "document_emailed",
          select: e.payload
        )
      )

    assert [%{"recipient" => "buyer", "email_message_id" => ^id} = payload] = entries
    refute Jason.encode!(payload) =~ "example.test"
  end

  test "a typed address, in another language; without any address it says so", ctx do
    path = "#{ctx.base}/documents/#{ctx.retail.id}/email"

    assert %{"code" => "no_recipient"} =
             ctx.owner
             |> send_mail(path, %{idempotency_key: "email-key-0002"})
             |> json_response(422)

    assert %{"code" => "invalid_address"} =
             ctx.owner
             |> send_mail(path, %{idempotency_key: "email-key-0003", to: "not an address"})
             |> json_response(422)

    assert %{"email" => %{"recipient" => "address"}} =
             ctx.owner
             |> send_mail(path, %{
               idempotency_key: "email-key-0004",
               to: "accountant@example.test",
               language: "en"
             })
             |> json_response(202)

    email = assert_email_enqueued(kind: :fiscal_document, to: "accountant@example.test")
    assert email.locale == "en"
    assert email.text =~ "Total"

    # The outbox throttles one address.
    assert %{"code" => "throttled"} =
             ctx.owner
             |> send_mail(path, %{
               idempotency_key: "email-key-0005",
               to: "accountant@example.test"
             })
             |> json_response(429)
  end

  test "coaches cannot send and a demo business never sends", ctx do
    path = "#{ctx.base}/documents/#{ctx.with_buyer.id}/email"

    assert ctx.coach
           |> send_mail(path, %{idempotency_key: "email-key-0006"})
           |> json_response(403)

    Repo.update_all(
      from(organization in "organizations",
        where: organization.id == type(^ctx.organization.id, :binary_id)
      ),
      set: [activation: "demo"]
    )

    assert %{"code" => "business_not_activated"} =
             ctx.owner
             |> send_mail(path, %{idempotency_key: "email-key-0007"})
             |> json_response(403)

    refute_email_enqueued(kind: :fiscal_document)
  end
end
