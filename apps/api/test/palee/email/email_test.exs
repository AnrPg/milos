defmodule Palee.EmailTest do
  use Palee.DataCase, async: false
  use Oban.Testing, repo: Palee.Repo

  import Palee.EmailCase
  import Palee.TestFixtures

  alias Palee.{Email, Organizations}
  alias Palee.Workers.DeliverEmailJob

  @assigns %{name: "Jo", url: "https://palee.app/x"}

  test "enqueue stores the rendered, encrypted email with its job" do
    assert {:ok, message} =
             Email.enqueue(:sample_notice, " Jo@Box.test ", @assigns, locale: "el")

    assert %{status: "queued", kind: "sample_notice", to_address: "jo@box.test"} = message
    assert message.subject == "Hello Jo"
    assert message.message_id =~ ~r/\A<[0-9a-f-]{36}@example\.com>\z/
    refute message.encrypted_body =~ "Hello Jo"
    assert_enqueued(worker: DeliverEmailJob, args: %{"message_id" => message.id}, queue: :email)

    found = assert_email_enqueued(kind: :sample_notice, to: "jo@box.test")
    assert found.text =~ "Open:\nhttps://palee.app/x"
    assert found.html =~ "Λαμβάνεις αυτό το email"

    assert {:ok, %{status: "queued", attempts: 0}} = Email.status(message.id)
    assert {:error, :not_found} = Email.status(Ecto.UUID.generate())
  end

  test "a PDF attachment travels encrypted with the body and is cleared once sent (ADR-265)" do
    pdf = "%PDF-1.7 sample"
    attachment = %{filename: "R-000001.pdf", content_type: "application/pdf", data: pdf}

    assert {:error, :invalid_attachment} =
             Email.enqueue(:sample_notice, "jo@box.test", @assigns,
               attachments: [%{attachment | content_type: "application/x-msdownload"}]
             )

    assert {:error, :invalid_attachment} =
             Email.enqueue(:sample_notice, "jo@box.test", @assigns,
               attachments: [%{attachment | filename: "../R.pdf"}]
             )

    assert {:error, :attachment_too_large} =
             Email.enqueue(:sample_notice, "jo@box.test", @assigns,
               attachments: [%{attachment | data: :binary.copy("a", 5_000_001)}]
             )

    assert {:ok, message} =
             Email.enqueue(:sample_notice, "jo@box.test", @assigns, attachments: [attachment])

    refute message.encrypted_body =~ "PDF"
    assert deliver_enqueued_emails() == 1

    Swoosh.TestAssertions.assert_email_sent(fn sent ->
      assert [%Swoosh.Attachment{filename: "R-000001.pdf", data: ^pdf}] = sent.attachments
    end)

    assert %{encrypted_body: nil, status: "sent"} =
             Palee.Repo.get!(Palee.Email.Message, message.id)
  end

  test "an idempotency key enqueues once and lists by prefix" do
    opts = [idempotency_key: "sample:1:first"]
    assert {:ok, first} = Email.enqueue(:sample_notice, "jo@box.test", @assigns, opts)
    assert {:ok, again} = Email.enqueue(:sample_notice, "jo@box.test", @assigns, opts)
    assert first.id == again.id

    {:ok, _second} =
      Email.enqueue(:sample_notice, "jo@box.test", @assigns, idempotency_key: "sample:1:second")

    {:ok, _other} =
      Email.enqueue(:sample_notice, "jo@box.test", @assigns, idempotency_key: "sample:10:x")

    assert [%{idempotency_key: "sample:1:second"}, %{idempotency_key: "sample:1:first"}] =
             Email.list_by_idempotency_prefix("sample:1:")

    assert length(all_enqueued(worker: DeliverEmailJob)) == 3
  end

  test "refusals: unknown kind, invalid address, suppressed address" do
    assert {:error, :unknown_kind} = Email.enqueue(:nope, "jo@box.test", @assigns)
    assert {:error, :invalid_address} = Email.enqueue(:sample_notice, "not an address", @assigns)

    assert {:ok, _} = Email.suppress("JO@box.test", :bounce)
    assert Email.suppressed?("jo@box.test")
    assert {:error, :suppressed} = Email.enqueue(:sample_notice, "jo@box.test", @assigns)
    assert :ok = Email.unsuppress("jo@box.test")
    refute Email.suppressed?("jo@box.test")
    refute_email_enqueued(to: "jo@box.test")
  end

  test "the per-recipient throttle of the category applies without a template's own" do
    now = DateTime.utc_now()
    opts = [category: :security, now: now]

    assert {:ok, _} = Email.enqueue(:sample_notice, "jo@box.test", @assigns, opts)
    assert {:error, :throttled} = Email.enqueue(:sample_notice, "jo@box.test", @assigns, opts)
    assert {:ok, _} = Email.enqueue(:sample_notice, "other@box.test", @assigns, opts)
  end

  test "over the daily budget non-security mail is deferred, security mail refused past the cap" do
    put_budget(daily_budget: 0, hard_cap: 0)

    assert {:ok, %{status: "deferred", scheduled_at: until} = message} =
             Email.enqueue(:sample_notice, "jo@box.test", @assigns)

    assert DateTime.compare(until, DateTime.utc_now()) == :gt

    assert_enqueued(
      worker: DeliverEmailJob,
      args: %{"message_id" => message.id},
      scheduled_at: until
    )

    assert {:error, :over_budget} =
             Email.enqueue(:sample_notice, "sec@box.test", @assigns, category: :security)
  end

  test "a business in demo mode sends no transactional mail; security and account mail goes" do
    {:ok, organization} = Organizations.create_organization(%{name: "Demo Box"})

    Repo.query!(
      "UPDATE organizations SET activation = 'demo', provider_kind = 'gym' WHERE id = $1",
      [Ecto.UUID.dump!(organization.id)]
    )

    opts = [organization_id: organization.id]
    assert {:error, :not_live} = Email.enqueue(:sample_notice, "jo@box.test", @assigns, opts)

    assert {:ok, _} =
             Email.enqueue(:sample_notice, "jo@box.test", @assigns, [category: :account] ++ opts)

    activate_business!(organization.id)
    assert {:ok, _} = Email.enqueue(:sample_notice, "jo@box.test", @assigns, opts)
  end

  test "deliver_enqueued_emails sends through the Swoosh test adapter" do
    {:ok, message} = Email.enqueue(:sample_notice, "jo@box.test", @assigns)
    assert deliver_enqueued_emails() == 1

    import Swoosh.TestAssertions

    assert_email_sent(fn email ->
      email.subject == "Hello Jo" and email.headers["Message-ID"] == message.message_id
    end)

    assert %{status: "sent", text: nil} = assert_email_enqueued(to: "jo@box.test")
  end

  defp put_budget(budget) do
    previous = Application.get_env(:palee, :email_budget)
    Application.put_env(:palee, :email_budget, budget)
    on_exit(fn -> Application.put_env(:palee, :email_budget, previous) end)
  end
end
