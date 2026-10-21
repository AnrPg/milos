defmodule Palee.Workers.DeviceJobsTest do
  use Palee.DataCase, async: false

  import Palee.TestFixtures

  alias Palee.Application.{GarminConnection, MyBody}
  alias Palee.{Devices, FakeGarminClient}
  alias Palee.Identity.UserContext
  alias Palee.Workers.{DeviceBackfillJob, DeviceIngestJob, DeviceMaintenanceJob}

  setup do
    FakeGarminClient.configure()
    on_exit(&FakeGarminClient.reset/0)
    user = user_fixture()
    context = UserContext.new(user)
    {:ok, _consents} = MyBody.grant(context, "health_data")

    {:ok, _url} = GarminConnection.connect(context, %{"backfill_days" => 0})
    assert_received {:garmin, :authorize_url, %{state: state}}
    {:ok, :connected} = GarminConnection.complete(%{"state" => state, "code" => "c"})

    connection =
      Devices.with_context(context, fn -> Devices.get_connection(user.id, "garmin") end)

    %{user: user, context: context, connection: connection}
  end

  test "the ingest job imports a push batch and pulls a ping callback", ctx do
    args = %{
      "connection_id" => ctx.connection.id,
      "user_id" => ctx.user.id,
      "type" => "activities",
      "summaries" => [
        %{
          "userId" => "garmin-user-1",
          "summaryId" => "j-1",
          "activityType" => "CYCLING",
          "startTimeInSeconds" => 1_792_000_000,
          "durationInSeconds" => 3600
        }
      ]
    }

    assert :ok = DeviceIngestJob.perform(%Oban.Job{args: args})

    FakeGarminClient.configure(
      fetch:
        {:ok,
         [
           %{
             "userId" => "garmin-user-1",
             "summaryId" => "j-2",
             "activityType" => "WALKING",
             "startTimeInSeconds" => 1_792_100_000,
             "durationInSeconds" => 1200
           }
         ]}
    )

    ping =
      args
      |> Map.delete("summaries")
      |> Map.put("callback_url", "https://apis.garmin.com/wellness-api/rest/activities?token=t")

    assert :ok = DeviceIngestJob.perform(%Oban.Job{args: ping})

    assert {:cancel, :invalid_callback_url} =
             DeviceIngestJob.perform(%Oban.Job{
               args: Map.put(ping, "callback_url", "https://evil.test/x")
             })

    sports =
      Devices.with_context(ctx.context, fn ->
        ctx.user.id |> Devices.list_activity_items(:none, 10, :owner) |> Enum.map(& &1.sport)
      end)

    assert Enum.sort(sports) == ["ride", "walk"]

    assert %{last_synced_at: %DateTime{}} =
             Devices.with_context(ctx.context, fn ->
               Devices.get_connection(ctx.user.id, "garmin")
             end)
  end

  test "the backfill job asks Garmin for each window and finishes", ctx do
    {:ok, _running} =
      Devices.with_context(ctx.context, fn ->
        Devices.update_connection(ctx.connection, %{
          backfill_days: 30,
          backfill_status: "running",
          backfill_windows_total: 3,
          backfill_windows_done: 0
        })
      end)

    assert :ok =
             DeviceBackfillJob.perform(%Oban.Job{
               args: %{"connection_id" => ctx.connection.id, "user_id" => ctx.user.id}
             })

    assert %{backfill_status: "done", backfill_windows_done: 3} =
             Devices.with_context(ctx.context, fn ->
               Devices.get_connection(ctx.user.id, "garmin")
             end)
  end

  test "the maintenance job refreshes tokens that end soon", ctx do
    {:ok, _soon} =
      Devices.with_context(ctx.context, fn ->
        Devices.update_connection(ctx.connection, %{
          token_expires_at: DateTime.add(DateTime.utc_now(), 300)
        })
      end)

    assert :ok = DeviceMaintenanceJob.perform(%Oban.Job{args: %{}})
    assert_received {:garmin, :refresh, "refresh-1"}

    assert %{access_token: "access-refreshed", refresh_token: "refresh-2"} =
             Devices.with_context(ctx.context, fn ->
               Devices.get_connection(ctx.user.id, "garmin")
             end)
  end
end
