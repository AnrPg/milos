defmodule Palee.Application.SmtpKeyExpiryCheckTest do
  # ADR-212: vendors are told before the SMTP key expires.
  use Palee.DataCase, async: false
  use Oban.Testing, repo: Palee.Repo

  import Ecto.Query
  import ExUnit.CaptureLog
  import Palee.TestFixtures

  alias Palee.Application.SmtpKeyExpiryCheck
  alias Palee.Notifications.Notification
  alias Palee.Workers.{NotificationEventJob, SmtpKeyExpiryJob}
  alias Palee.{Organizations, Repo}

  setup do
    previous = Application.get_env(:palee, :smtp_key_expires_on)
    Application.put_env(:palee, :smtp_key_expires_on, ~D[2027-10-26])
    on_exit(fn -> Application.put_env(:palee, :smtp_key_expires_on, previous) end)

    vendor = user_fixture()
    {:ok, _vendor} = Organizations.grant_vendor(vendor.id)
    member = user_fixture()

    ref = make_ref()
    pid = self()

    :telemetry.attach(
      {__MODULE__, ref},
      [:palee, :email, :smtp_key],
      fn _event, measurements, _meta, _config -> send(pid, {:smtp_key, measurements}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach({__MODULE__, ref}) end)
    %{vendor: vendor, member: member}
  end

  defp alerts(user_id) do
    for job <- all_enqueued(worker: NotificationEventJob),
        do: perform_job(NotificationEventJob, job.args)

    bypass_rls(fn ->
      Repo.all(
        from n in Notification,
          where: n.type == :email_key_expiring and n.user_id == ^user_id,
          select: n.payload
      )
    end)
  end

  test "quiet and only measured while the key has more than 30 days", %{vendor: vendor} do
    assert {:ok, :ok} = SmtpKeyExpiryCheck.call(~D[2027-09-01])
    assert_received {:smtp_key, %{days_left: 55}}
    assert alerts(vendor.id) == []
  end

  test "30 days before: a warning and a bell notification to each vendor only", ctx do
    log = capture_log(fn -> assert {:ok, :notified} = SmtpKeyExpiryCheck.call(~D[2027-09-26]) end)

    assert log =~ "smtp_key_expiring days_left=30 expires_on=2027-10-26"

    assert [%{"days_left" => 30, "expires_on" => "2027-10-26", "url" => "/platform"}] =
             alerts(ctx.vendor.id)

    assert alerts(ctx.member.id) == []

    # Between the reminder days it only logs.
    capture_log(fn -> assert {:ok, :quiet} = SmtpKeyExpiryCheck.call(~D[2027-09-27]) end)
  end

  test "once expired, every day, as an error", %{vendor: vendor} do
    log = capture_log(fn -> assert {:ok, :notified} = SmtpKeyExpiryCheck.call(~D[2027-10-28]) end)

    assert log =~ "smtp_key_expired"
    assert [%{"days_left" => -2, "title" => "The email key has expired"}] = alerts(vendor.id)
  end

  test "unset: nothing to check" do
    Application.put_env(:palee, :smtp_key_expires_on, nil)
    assert {:ok, :unknown} = SmtpKeyExpiryCheck.call(~D[2027-10-28])
    refute_received {:smtp_key, _}
    assert :ok = perform_job(SmtpKeyExpiryJob, %{})
  end
end
