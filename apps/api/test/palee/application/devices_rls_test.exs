defmodule Palee.Application.DevicesRLSTest do
  @moduledoc """
  ADR-161 under real Row Level Security: Garmin's connection, imports and
  watch workouts are the member's own; nobody else reads them; a coach sees
  the watch's numbers only on an entry that reaches them. The import
  pipeline merges, asks, dedupes, respects the sync preferences and lets
  what the member typed win.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.TestFixtures
  import Ecto.Query

  alias Palee.Application.{
    DeviceImports,
    DeviceMaintenance,
    GarminConnection,
    GarminPush,
    GetClientJournal,
    GetJournalFeed,
    ImportDeviceSummaries,
    LogWellnessEntry,
    MyBody
  }

  alias Palee.{Body, Devices, FakeGarminClient, Organizations, Repo, Wellness}
  alias Palee.Execution.TrainingLogEntry
  alias Palee.Identity.UserContext
  alias Palee.Notifications.Notification

  @start ~U[2026-10-20 18:00:00.000000Z]

  setup do
    FakeGarminClient.configure()
    on_exit(&FakeGarminClient.reset/0)

    fixtures =
      bypass_rls(fn ->
        {:ok, gym} = Organizations.create_organization(%{name: "Garmin Gym"})
        coach = user_fixture()
        member = user_fixture()
        other = user_fixture()
        add!(gym, coach, :coach)
        add!(gym, member, :member)
        %{gym: gym, coach: coach, member: member, other: other}
      end)

    member_ctx = UserContext.new(fixtures.member)
    {:ok, _consents} = MyBody.grant(member_ctx, "health_data", ~U[2026-10-01 00:00:00.000000Z])

    Map.merge(fixtures, %{
      member_ctx: member_ctx,
      other_ctx: UserContext.new(fixtures.other),
      coach_ctx: tenant!(fixtures.coach, fixtures.gym)
    })
  end

  defp connect!(ctx, params \\ %{"backfill_days" => 0}) do
    {:ok, %{authorize_url: url}} = GarminConnection.connect(ctx.member_ctx, params)
    assert_received {:garmin, :authorize_url, %{state: state, challenge: challenge}}
    assert url =~ challenge
    assert {:ok, :connected} = GarminConnection.complete(%{"state" => state, "code" => "code-1"})
    assert_received {:garmin, :exchange_code, %{verifier: verifier}}
    assert Devices.pkce_challenge(verifier) == challenge
    connection(ctx)
  end

  defp connection(ctx) do
    Devices.with_context(ctx.member_ctx, fn ->
      Devices.get_connection(ctx.member.id, "garmin")
    end)
  end

  defp push!(ctx, type, summaries) do
    connection = connection(ctx)

    {:ok, counts} =
      ImportDeviceSummaries.run(%{
        "connection_id" => connection.id,
        "user_id" => ctx.member.id,
        "type" => type,
        "summaries" => Enum.map(summaries, &Map.put(&1, "userId", "garmin-user-1"))
      })

    counts
  end

  defp activity(id, start, minutes, extra \\ %{}) do
    Map.merge(
      %{
        "summaryId" => id,
        "activityType" => "STRENGTH_TRAINING",
        "startTimeInSeconds" => DateTime.to_unix(start),
        "startTimeOffsetInSeconds" => 10_800,
        "durationInSeconds" => minutes * 60,
        "averageHeartRateInBeatsPerMinute" => 148,
        "activeKilocalories" => 500
      },
      extra
    )
  end

  defp log!(ctx, start, minutes, visibility) do
    bypass_rls(fn ->
      Repo.insert!(%TrainingLogEntry{
        organization_id: ctx.gym.id,
        user_id: ctx.member.id,
        source_type: "freeform",
        title: "CrossFit 18:00",
        performed_at_utc: start,
        duration_seconds: minutes * 60,
        idempotency_key: Ecto.UUID.generate(),
        journal_visibility: visibility
      })
    end)
  end

  test "connecting keeps the verifier and tokens encrypted at rest", ctx do
    connection = connect!(ctx)
    assert connection.status == "active"
    assert connection.provider_user_id == "garmin-user-1"
    assert connection.access_token == "access-1"
    assert connection.pkce_verifier == nil

    [[access, refresh]] =
      bypass_rls(fn ->
        Repo.query!(
          "SELECT access_token, refresh_token FROM device_connections WHERE id = $1",
          [Ecto.UUID.dump!(connection.id)]
        ).rows
      end)

    refute access =~ "access-1"
    refute refresh =~ "refresh-1"

    # Nobody else reads the connection.
    assert nil ==
             Devices.with_context(ctx.other_ctx, fn ->
               Repo.one(from(c in Devices.Connection, where: c.id == ^connection.id))
             end)
  end

  test "a run becomes its own private entry once, and only its owner sees it", ctx do
    connect!(ctx)
    run = activity("run-1", ~U[2026-10-20 07:10:00Z], 34, %{"activityType" => "RUNNING"})

    assert %{imported: 1} = push!(ctx, "activities", [run])
    assert %{duplicate: 1} = push!(ctx, "activities", [run])

    {:ok, %{items: [item]}} = GetJournalFeed.call(ctx.member_ctx, %{"kinds" => "device_activity"})
    assert item.kind == "device_activity"
    assert item.journal_visibility == "private"
    assert item.choosable_visibilities == ["private"]
    assert %{sport: "run", avg_heart_rate: 148, title: "Running"} = item.entry

    {:ok, %{items: []}} = GetJournalFeed.call(ctx.other_ctx, %{"kinds" => "device_activity"})

    assert [] ==
             Devices.with_context(ctx.other_ctx, fn -> Repo.all(Devices.DeviceActivity) end)
  end

  test "an activity overlapping a logged workout adds the watch's numbers to it", ctx do
    connect!(ctx)
    log = log!(ctx, @start, 60, "private")

    assert %{merged: 1} =
             push!(ctx, "activities", [activity("wod-1", DateTime.add(@start, 120), 52)])

    {:ok, %{items: [item]}} =
      GetJournalFeed.call(ctx.member_ctx, %{"kinds" => "training_log,device_activity"})

    assert item.kind == "training_log"
    assert item.id == log.id
    assert %{avg_heart_rate: 148, calories: 500, provider: "garmin"} = item.entry.device

    # The numbers follow the entry: hidden from the coach while it is private.
    assert [] = coach_device_rows(ctx)

    bypass_rls(fn ->
      log |> Ecto.Changeset.change(journal_visibility: "coach_can_view") |> Repo.update!()
    end)

    assert [_row] = coach_device_rows(ctx)

    {:ok, %{items: [coach_item]}} =
      GetClientJournal.call(ctx.coach_ctx, ctx.member.id, %{"kinds" => "training_log"})

    assert %{avg_heart_rate: 148} = coach_item.entry.device
  end

  test "two possible matches wait for the member's answer", ctx do
    connect!(ctx)
    first = log!(ctx, @start, 60, "private")
    second = log!(ctx, DateTime.add(@start, 600), 60, "private")

    assert %{needs_confirmation: 1} =
             push!(ctx, "activities", [activity("wod-2", DateTime.add(@start, 300), 50)])

    assert {:ok, %{needs_confirmation: 1, visible: true}} = DeviceImports.summary(ctx.member_ctx)
    {:ok, [pending]} = DeviceImports.pending(ctx.member_ctx)

    assert pending.activity.candidates |> Enum.map(& &1.id) |> Enum.sort() ==
             Enum.sort([first.id, second.id])

    assert {:error, :unknown_device_candidate} =
             DeviceImports.confirm(ctx.member_ctx, pending.id, %{
               "target_id" => Ecto.UUID.generate()
             })

    assert {:ok, %{state: "merged"}} =
             DeviceImports.confirm(ctx.member_ctx, pending.id, %{"target_id" => second.id})

    assert {:error, :import_already_settled} =
             DeviceImports.confirm(ctx.member_ctx, pending.id, %{"as_new" => true})

    {:ok, %{items: items}} = GetJournalFeed.call(ctx.member_ctx, %{"kinds" => "training_log"})
    assert Enum.find(items, &(&1.id == second.id)).entry.device
    refute Enum.find(items, &(&1.id == first.id)).entry.device

    {:ok, summary} = DeviceImports.mark_seen(ctx.member_ctx)
    refute summary.visible
  end

  test "a night fills Ευεξία unless the member typed one; a scale fills Σώμα", ctx do
    connect!(ctx)

    night = %{
      "summaryId" => "sleep-1",
      "calendarDate" => "2026-10-19",
      "startTimeInSeconds" => DateTime.to_unix(~U[2026-10-18 21:00:00Z]),
      "startTimeOffsetInSeconds" => 10_800,
      "durationInSeconds" => 7 * 3600,
      "overallSleepScore" => %{"qualifierKey" => "GOOD"}
    }

    assert %{imported: 1} = push!(ctx, "sleeps", [night])

    [entry] =
      Wellness.with_context(ctx.member_ctx, fn ->
        Wellness.list_entries(ctx.member.id, ~D[2026-10-19], ~D[2026-10-19])
      end)

    assert %{
             source: "garmin",
             journal_visibility: "private",
             value: %{"minutes" => 420, "quality" => 4}
           } =
             entry

    {:ok, _typed} =
      LogWellnessEntry.call(
        ctx.member_ctx,
        %{
          "kind" => "sleep",
          "value" => %{"minutes" => 400, "quality" => 3},
          "occurred_on" => "2026-10-20"
        },
        ~U[2026-10-20 08:00:00Z]
      )

    second = %{night | "summaryId" => "sleep-2", "calendarDate" => "2026-10-20"}
    assert %{merged: 1} = push!(ctx, "sleeps", [second])

    [only] =
      Wellness.with_context(ctx.member_ctx, fn ->
        Wellness.list_entries(ctx.member.id, ~D[2026-10-20], ~D[2026-10-20])
      end)

    assert only.source == "manual"

    weigh_in = %{
      "summaryId" => "w-1",
      "measurementTimeInSeconds" => DateTime.to_unix(~U[2026-10-20 06:00:00Z]),
      "weightInGrams" => 72_400
    }

    assert %{imported: 1} = push!(ctx, "bodyComps", [weigh_in])

    assert [%{source: "garmin", visibility: "private", metrics: %{"weight" => 72.4}}] =
             Body.list_snapshots(ctx.member_ctx, ctx.member.id, [])

    assert %{imported: 1} =
             push!(ctx, "dailies", [
               %{
                 "summaryId" => "d-1",
                 "calendarDate" => "2026-10-20",
                 "restingHeartRateInBeatsPerMinute" => 51
               }
             ])

    assert [%{resting_heart_rate: 51}] =
             Devices.with_context(ctx.member_ctx, fn ->
               Devices.list_daily_stats(ctx.member.id, ~D[2026-10-01], ~D[2026-10-31])
             end)
  end

  test "a typed weight the same day wins over the scale", ctx do
    connect!(ctx)

    {:ok, _snapshot} =
      Palee.Application.BodySnapshots.create(ctx.member_ctx, %{
        "metrics" => %{"weight" => 73},
        "taken_at" => "2026-10-20T07:00:00Z"
      })

    assert %{merged: 1} =
             push!(ctx, "bodyComps", [
               %{
                 "summaryId" => "w-2",
                 "measurementTimeInSeconds" => DateTime.to_unix(~U[2026-10-20 06:00:00Z]),
                 "weightInGrams" => 72_400
               }
             ])

    assert [%{source: "manual"}] = Body.list_snapshots(ctx.member_ctx, ctx.member.id, [])
  end

  test "switched-off kinds are not imported at all", ctx do
    connect!(ctx, %{"backfill_days" => 0, "sync_prefs" => %{"weight" => false}})

    assert %{skipped: 1} =
             push!(ctx, "bodyComps", [
               %{
                 "summaryId" => "w-3",
                 "measurementTimeInSeconds" => 1_792_000_000,
                 "weightInGrams" => 70_000
               }
             ])

    assert [] = Body.list_snapshots(ctx.member_ctx, ctx.member.id, [])

    assert {:ok, %{sync_prefs: %{"weight" => true}}} =
             GarminConnection.update(ctx.member_ctx, %{"sync_prefs" => %{"weight" => true}})
  end

  test "pushes are verified and routed to the right person; unknown users are ignored", ctx do
    connect!(ctx)

    assert {:error, :invalid_push} =
             GarminPush.accept(%{"activities" => []}, %{client_id: "someone", token: nil})

    body = %{
      "activities" => [
        Map.put(activity("p-1", ~U[2026-10-20 07:00:00Z], 30), "userId", "garmin-user-1"),
        Map.put(activity("p-2", ~U[2026-10-20 07:00:00Z], 30), "userId", "stranger")
      ]
    }

    verification = %{client_id: FakeGarminClient.client_id(), token: nil}
    assert {:ok, %{queued: 1, ignored: 1}} = GarminPush.accept(body, verification)
    assert {:ok, %{queued: 1}} = GarminPush.accept(body, verification)

    assert [_one] =
             Devices.with_context(ctx.member_ctx, fn -> Repo.all(Devices.DeviceActivity) end)

    assert {:ok, %{deregistered: 1}} =
             GarminPush.deregister(
               %{"deregistrations" => [%{"userId" => "garmin-user-1"}]},
               verification
             )

    assert %{status: "revoked", access_token: nil} = connection(ctx)
  end

  test "disconnecting keeps the data, or deletes everything Garmin brought", ctx do
    connect!(ctx)
    push!(ctx, "activities", [activity("k-1", ~U[2026-10-20 07:00:00Z], 30)])

    assert {:ok, %{status: "revoked", deleted: nil}} =
             GarminConnection.disconnect(ctx.member_ctx, false)

    assert_received {:garmin, :deregister, "access-1"}

    {:ok, %{items: [_kept]}} =
      GetJournalFeed.call(ctx.member_ctx, %{"kinds" => "device_activity"})

    connect!(ctx)

    assert {:ok, %{deleted: %{activities: 1, imports: 1}}} =
             GarminConnection.disconnect(ctx.member_ctx, true)

    {:ok, %{items: []}} = GetJournalFeed.call(ctx.member_ctx, %{"kinds" => "device_activity"})
  end

  test "history is asked window by window; sync now is rate limited", ctx do
    connection = connect!(ctx, %{"backfill_days" => 30})
    assert %{backfill_status: "done", backfill_windows_done: 3} = connection

    asked = for {:garmin, :request_backfill, {_t, type, _f, _to}} <- messages(), do: type
    assert length(asked) == 12
    assert "activities" in asked

    assert {:ok, %{status: "connected"}} = GarminConnection.sync_now(ctx.member_ctx)
    assert {:error, :sync_too_soon} = GarminConnection.sync_now(ctx.member_ctx)
  end

  test "repeated refresh failures turn the connection to error and notify once", ctx do
    connection = connect!(ctx)
    FakeGarminClient.configure(refresh: {:error, :garmin_unavailable})
    now = DateTime.add(connection.token_expires_at, -60)

    for _attempt <- 1..4, do: DeviceMaintenance.refresh(connection.id, ctx.member.id, now)

    assert %{status: "error", consecutive_failures: 4} = connection(ctx)

    assert {:ok, %{garmin: %{status: "error", connection: %{needs_reconnect: true}}}} =
             Palee.Application.ConnectedDevices.call(ctx.member_ctx, ctx.member)
             |> then(fn {:ok, devices} ->
               {:ok, %{garmin: Enum.find(devices.integrations, &(&1.provider == "garmin"))}}
             end)

    notices =
      bypass_rls(fn ->
        Repo.all(
          from(n in Notification,
            where: n.user_id == ^ctx.member.id and n.type == :device_sync_error
          )
        )
      end)

    assert length(notices) == 1
  end

  test "Garmin is «Σύντομα» without credentials, and connecting says so", ctx do
    FakeGarminClient.reset()
    assert %{status: "unavailable", configured: false} = GarminConnection.row(ctx.member_ctx)

    assert {:error, :garmin_not_configured} =
             GarminConnection.connect(ctx.member_ctx, %{})
  end

  defp coach_device_rows(ctx) do
    Devices.with_context(ctx.coach_ctx, fn -> Repo.all(Devices.DeviceActivity) end)
  end

  defp messages do
    receive do
      message -> [message | messages()]
    after
      0 -> []
    end
  end

  defp add!(organization, user, role) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    membership
  end

  defp tenant!(user, organization) do
    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    context
  end
end
