defmodule Palee.Workers.DeliverEmailJobTest do
  use Palee.DataCase, async: false
  use Oban.Testing, repo: Palee.Repo

  import Swoosh.TestAssertions

  alias Palee.Email
  alias Palee.TestSupport.TelemetryCapture
  alias Palee.Workers.DeliverEmailJob

  defmodule FailingSender do
    @behaviour Palee.Email.Ports.Sender
    @impl true
    def deliver(_email),
      do: Process.get(:email_sender_result, {:error, :mail_delivery_unavailable})
  end

  @assigns %{name: "Jo", url: "https://palee.app/x"}

  setup do
    TelemetryCapture.capture(
      for(event <- [:sent, :failed, :suppressed, :deferred], do: [:palee, :email, event])
    )

    {:ok, message} = Email.enqueue(:sample_notice, "jo@box.test", @assigns)
    %{message: message}
  end

  defp perform(message, attempt \\ 1) do
    perform_job(DeliverEmailJob, %{"message_id" => message.id}, attempt: attempt)
  end

  test "sends the email, records the outcome and clears the body", %{message: message} do
    assert :ok = perform(message)

    assert_email_sent(fn email ->
      email.to == [{"", "jo@box.test"}] and email.subject == "Hello Jo" and
        email.headers["Message-ID"] == message.message_id and email.html_body =~ "Hello Jo"
    end)

    assert {:ok, %{status: "sent", attempts: 1, sent_at: %DateTime{}}} = Email.status(message.id)
    assert %{encrypted_body: nil} = Palee.Email.message_store().get(message.id)

    assert_received {:telemetry_event, [:palee, :email, :sent], %{count: 1},
                     %{kind: "sample_notice"}}

    # A repeat (Oban retrying after a crash) sends nothing more.
    assert :ok = perform(message)
    refute_email_sent()
  end

  test "a provider failure is retried, and recorded as failed after the last attempt",
       %{message: message} do
    swap_sender(FailingSender)

    assert {:error, :mail_delivery_unavailable} = perform(message)

    assert {:ok, %{status: "queued", attempts: 1, last_error: ":mail_delivery_unavailable"}} =
             Email.status(message.id)

    refute_received {:telemetry_event, [:palee, :email, :failed], _, _}

    assert {:error, :mail_delivery_unavailable} = perform(message, 8)
    assert {:ok, %{status: "failed", attempts: 2}} = Email.status(message.id)
    assert_received {:telemetry_event, [:palee, :email, :failed], _, %{reason: _}}
  end

  test "a permanent failure is not retried", %{message: message} do
    swap_sender(FailingSender)
    Process.put(:email_sender_result, {:error, {:send, {:permanent_failure, "relay", "550"}}})

    assert {:cancel, _reason} = perform(message)
    assert {:ok, %{status: "failed"}} = Email.status(message.id)
  end

  test "an address suppressed after enqueue is skipped", %{message: message} do
    {:ok, _} = Email.suppress("jo@box.test", :complaint)

    assert :ok = perform(message)
    refute_email_sent()
    assert {:ok, %{status: "suppressed"}} = Email.status(message.id)
    assert_received {:telemetry_event, [:palee, :email, :suppressed], _, _}
  end

  test "over the budget the email is deferred to the next UTC day", %{message: message} do
    previous = Application.get_env(:palee, :email_budget)
    Application.put_env(:palee, :email_budget, daily_budget: 0, hard_cap: 10)
    on_exit(fn -> Application.put_env(:palee, :email_budget, previous) end)

    assert {:snooze, seconds} = perform(message)
    assert seconds > 0 and seconds <= 86_460
    refute_email_sent()
    assert {:ok, %{status: "deferred", scheduled_at: %DateTime{}}} = Email.status(message.id)
    assert_received {:telemetry_event, [:palee, :email, :deferred], _, _}

    # Security mail still goes until the hard cap.
    {:ok, security} =
      Email.enqueue(:sample_notice, "sec@box.test", @assigns, category: :security)

    assert :ok = perform(security)
    assert_email_sent(to: [{"", "sec@box.test"}])
  end

  test "a missing message is nothing to do" do
    assert :ok = perform_job(DeliverEmailJob, %{"message_id" => Ecto.UUID.generate()})
  end

  defp swap_sender(sender) do
    previous = Application.fetch_env!(:palee, :email_sender)
    Application.put_env(:palee, :email_sender, sender)
    on_exit(fn -> Application.put_env(:palee, :email_sender, previous) end)
  end
end
