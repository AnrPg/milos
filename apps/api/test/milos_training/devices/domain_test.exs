defmodule MilosTraining.Devices.DomainTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Devices.Domain.{
    ActivityMatch,
    Catalog,
    ConnectionPolicy,
    GarminSummary,
    ImportPolicy,
    LocalTime,
    Pkce,
    Sport
  }

  @start 1_792_000_000

  describe "Garmin activity mapping" do
    test "maps sport, start, duration, distance, heart rate and calories" do
      summary = %{
        "userId" => "g-1",
        "summaryId" => "123-detail",
        "activityId" => 123,
        "activityName" => "Πρωινό τρέξιμο",
        "activityType" => "RUNNING",
        "startTimeInSeconds" => @start,
        "startTimeOffsetInSeconds" => 10_800,
        "durationInSeconds" => 2040,
        "distanceInMeters" => 6200.5,
        "averageHeartRateInBeatsPerMinute" => 148,
        "maxHeartRateInBeatsPerMinute" => 171,
        "activeKilocalories" => 412,
        "polyline" => "never kept"
      }

      assert {:ok, activity} = GarminSummary.activity(summary)
      assert activity.provider_id == "123-detail"
      assert activity.sport == "run"
      assert activity.title == "Πρωινό τρέξιμο"
      assert activity.started_at == DateTime.from_unix!(@start * 1_000_000, :microsecond)
      assert activity.started_tz == "Etc/GMT-3"
      assert activity.duration_seconds == 2040
      assert activity.distance_meters == 6200.5

      assert {activity.avg_heart_rate, activity.max_heart_rate, activity.calories} ==
               {148, 171, 412}

      refute Map.has_key?(GarminSummary.trim("activity", summary), "polyline")
    end

    test "a summary without a start or duration is refused; odd heart rates are dropped" do
      assert {:error, :missing_start} = GarminSummary.activity(%{"durationInSeconds" => 60})

      assert {:ok, %{avg_heart_rate: nil, title: nil}} =
               GarminSummary.activity(%{
                 "summaryId" => "x",
                 "startTimeInSeconds" => @start,
                 "durationInSeconds" => 60,
                 "averageHeartRateInBeatsPerMinute" => 900,
                 "activityName" => "  "
               })
    end

    test "sports fold Garmin's types, unknown ones become other" do
      assert Sport.of("STRENGTH_TRAINING") == "strength"
      assert Sport.of("INDOOR_TRACK_RUNNING") == "run"
      assert Sport.of("LAP_SWIMMING") == "swim"
      assert Sport.of("HIIT") == "hiit"
      assert Sport.of("SNOWSHOE") == "other"
      assert Sport.of(nil) == "other"
    end

    test "summary types map to import kinds" do
      assert GarminSummary.kind("activities") == "activity"
      assert GarminSummary.kind("sleeps") == "sleep"
      assert GarminSummary.kind("bodyComps") == "weight"
      assert GarminSummary.kind("dailies") == "daily"
      assert GarminSummary.kind("epochs") == nil
      assert Enum.sort(GarminSummary.backfill_types(["sleep", "daily"])) == ["dailies", "sleeps"]
    end
  end

  describe "sleep, weight and daily mapping" do
    test "a night counts on Garmin's calendar date with a quality from its score" do
      assert {:ok, night} =
               GarminSummary.sleep(%{
                 "summaryId" => "s-1",
                 "calendarDate" => "2026-10-20",
                 "startTimeInSeconds" => @start,
                 "startTimeOffsetInSeconds" => 10_800,
                 "durationInSeconds" => 25_200,
                 "overallSleepScore" => %{"value" => 83, "qualifierKey" => "GOOD"}
               })

      assert night.on == ~D[2026-10-20]
      assert DateTime.diff(night.wake_at, night.bed_at) == 25_200
      assert night.quality == 4

      assert {:ok, %{quality: 2}} =
               GarminSummary.sleep(%{
                 "summaryId" => "s-2",
                 "startTimeInSeconds" => @start,
                 "durationInSeconds" => 3600,
                 "overallSleepScore" => %{"value" => 45}
               })
    end

    test "a weigh-in is kept in kilograms with body fat" do
      assert {:ok, %{metrics: %{"weight" => 72.4, "body_fat" => 18.5}}} =
               GarminSummary.weight(%{
                 "summaryId" => "w-1",
                 "measurementTimeInSeconds" => @start,
                 "weightInGrams" => 72_400,
                 "bodyFatInPercent" => 18.5
               })

      assert {:error, :missing_weight} =
               GarminSummary.weight(%{"summaryId" => "w", "measurementTimeInSeconds" => @start})
    end

    test "a day keeps its resting heart rate" do
      assert {:ok, %{on: ~D[2026-10-20], resting_heart_rate: 52}} =
               GarminSummary.daily(%{
                 "summaryId" => "d-1",
                 "calendarDate" => "2026-10-20",
                 "restingHeartRateInBeatsPerMinute" => 52
               })

      assert {:error, :missing_resting_heart_rate} =
               GarminSummary.daily(%{"summaryId" => "d", "calendarDate" => "2026-10-20"})
    end

    test "offsets become fixed zones and local days" do
      assert LocalTime.zone(10_800) == "Etc/GMT-3"
      assert LocalTime.zone(-18_000) == "Etc/GMT+5"
      assert LocalTime.zone(19_800) == "UTC"
      assert LocalTime.date(~U[2026-10-20 22:30:00Z], 10_800) == ~D[2026-10-21]
    end
  end

  describe "activity matching" do
    @class_start ~U[2026-10-20 18:00:00.000000Z]

    defp candidate(kind, id, starts_at, minutes) do
      %{kind: kind, id: id, starts_at: starts_at, ends_at: DateTime.add(starts_at, minutes * 60)}
    end

    defp activity(starts_at, minutes),
      do: %{started_at: starts_at, duration_seconds: minutes * 60}

    test "an activity starting within 15 minutes of a class merges into it" do
      class = candidate("training_log", "a", @class_start, 60)

      assert {:merge, ^class} =
               ActivityMatch.decide(activity(DateTime.add(@class_start, 14 * 60), 52), [class])
    end

    test "half of the shorter one overlapping also matches; less does not" do
      class = candidate("execution", "a", @class_start, 60)
      # Starts 30 minutes in and runs 40: 30 of 40 minutes overlap.
      assert {:merge, _} =
               ActivityMatch.decide(activity(DateTime.add(@class_start, 30 * 60), 40), [class])

      # Starts 50 minutes in: 10 of 40 minutes overlap.
      assert :none =
               ActivityMatch.decide(activity(DateTime.add(@class_start, 50 * 60), 40), [class])
    end

    test "two possible matches ask the member; taken entries never match again" do
      first = candidate("training_log", "a", @class_start, 60)
      second = candidate("class", "b", DateTime.add(@class_start, 10 * 60), 60)
      run = activity(DateTime.add(@class_start, 5 * 60), 50)

      assert {:ambiguous, [^first, ^second]} = ActivityMatch.decide(run, [second, first])

      assert {:merge, ^second} =
               ActivityMatch.decide(run, [first, second], [{"training_log", "a"}])
    end

    test "a run hours away from any class is its own entry" do
      class = candidate("training_log", "a", @class_start, 60)
      assert :none = ActivityMatch.decide(activity(~U[2026-10-20 07:10:00.000000Z], 34), [class])
    end
  end

  describe "sync preferences and backfill" do
    test "only sleep, weight and resting heart rate are health data" do
      refute Catalog.health_data?(%{
               "activities" => true,
               "sleep" => false,
               "weight" => false,
               "resting_hr" => false
             })

      assert Catalog.health_data?(%{"activities" => true, "sleep" => false, "weight" => false})
      assert Catalog.health_data?(%{"resting_hr" => true})
      assert Catalog.health_data?(Catalog.default_prefs())
    end

    test "everything is on by default; changes are booleans of known keys" do
      assert Catalog.default_prefs() == %{
               "activities" => true,
               "sleep" => true,
               "weight" => true,
               "resting_hr" => true
             }

      assert {:ok, %{"weight" => false, "sleep" => true}} =
               Catalog.merge_prefs(%{}, %{weight: false})

      assert {:error, :invalid_sync_prefs} = Catalog.merge_prefs(%{}, %{"steps" => true})
      assert {:error, :invalid_sync_prefs} = Catalog.merge_prefs(%{}, %{"sleep" => "yes"})
      refute Catalog.wanted?(%{"weight" => false}, "weight")
      assert Catalog.wanted?(%{"weight" => false}, "activity")
      refute Catalog.wanted?(%{"resting_hr" => false}, "daily")
    end

    test "history goes 0, 30 or 90 days back, 30 by default" do
      assert {:ok, 30} = Catalog.validate_backfill_days(nil)
      assert {:ok, 90} = Catalog.validate_backfill_days("90")
      assert {:error, :invalid_backfill_days} = Catalog.validate_backfill_days(7)
    end

    test "history is cut into 10-day windows with a progress" do
      now = ~U[2026-10-20 12:00:00.000000Z]
      windows = ConnectionPolicy.backfill_windows(30, now)
      assert length(windows) == 3
      assert {_from, ^now} = List.last(windows)
      assert ConnectionPolicy.backfill_windows(0, now) == []
      assert length(ConnectionPolicy.backfill_windows(90, now)) == 9

      running = %{backfill_status: "running", backfill_windows_total: 5, backfill_windows_done: 2}
      assert ConnectionPolicy.backfill_progress(running) == 40
      assert ConnectionPolicy.backfill_progress(%{running | backfill_status: "done"}) == 100
      assert ConnectionPolicy.backfill_progress(%{running | backfill_status: "none"}) == nil
    end
  end

  describe "connection life" do
    @now ~U[2026-10-20 12:00:00.000000Z]

    test "sync now at most every five minutes" do
      assert :ok = ConnectionPolicy.validate_sync_request(nil, @now)

      assert {:error, :sync_too_soon} =
               ConnectionPolicy.validate_sync_request(DateTime.add(@now, -60), @now)

      assert :ok = ConnectionPolicy.validate_sync_request(DateTime.add(@now, -301), @now)
    end

    test "the third failure in a row turns a connection to error and notifies once" do
      connection = %{status: "active", consecutive_failures: 1, error_notified_at: nil}

      assert {%{consecutive_failures: 2} = changes, false} =
               ConnectionPolicy.failure(connection, "x")

      refute Map.has_key?(changes, :status)

      assert {%{status: "error", consecutive_failures: 3}, true} =
               ConnectionPolicy.failure(%{connection | consecutive_failures: 2}, "x")

      assert {%{status: "error"}, false} =
               ConnectionPolicy.failure(
                 %{status: "error", consecutive_failures: 3, error_notified_at: @now},
                 "x"
               )

      assert %{status: "active", consecutive_failures: 0, error_notified_at: nil} =
               ConnectionPolicy.success(%{status: "error"}, @now)
    end

    test "tokens refresh half an hour early; sign-ins expire after 15 minutes" do
      assert ConnectionPolicy.refresh_due?(DateTime.add(@now, 600), @now)
      refute ConnectionPolicy.refresh_due?(DateTime.add(@now, 7200), @now)
      assert ConnectionPolicy.sign_in_expired?(DateTime.add(@now, -16 * 60), @now)
      refute ConnectionPolicy.sign_in_expired?(DateTime.add(@now, -60), @now)
    end

    test "the row status speaks the devices page's words" do
      assert ConnectionPolicy.row_status(nil, false) == "unavailable"
      assert ConnectionPolicy.row_status(nil, true) == "disconnected"
      assert ConnectionPolicy.row_status(%{status: "active"}, true) == "connected"
      assert ConnectionPolicy.row_status(%{status: "error"}, true) == "error"
    end
  end

  describe "PKCE" do
    test "the challenge is the S256 of the verifier (RFC 7636 appendix B)" do
      verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
      assert Pkce.challenge(verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
      assert Pkce.valid_verifier?(Pkce.verifier(:crypto.strong_rand_bytes(48)))
      refute Pkce.valid_verifier?("short")
      assert Pkce.state_hash("abc") == Pkce.state_hash("abc")
      refute Pkce.state_hash("abc") == "abc"
    end
  end

  describe "import rules" do
    test "a typed night wins over the watch; naps do not compete" do
      typed = %{id: "m", kind: "sleep", source: "manual", value: %{"nap" => false}}
      nap = %{id: "n", kind: "sleep", source: "manual", value: %{"nap" => true}}
      garmin = %{id: "g", kind: "sleep", source: "garmin", value: %{}}

      assert {:manual_wins, "m"} = ImportPolicy.sleep_decision([garmin, typed])
      assert :import = ImportPolicy.sleep_decision([nap, garmin])
    end

    test "a typed weight the same day wins over the scale" do
      assert {:manual_wins, "s"} =
               ImportPolicy.weight_decision([
                 %{id: "s", source: "manual", metrics: %{"weight" => 72}}
               ])

      assert :import =
               ImportPolicy.weight_decision([
                 %{id: "s", source: "manual", metrics: %{"waist" => 80}}
               ])
    end

    test "imports start private" do
      assert ImportPolicy.visibility() == "private"
    end

    test "the device card counts what is new since last seen" do
      seen = ~U[2026-10-20 10:00:00.000000Z]
      later = ~U[2026-10-20 11:00:00.000000Z]

      imports = [
        %{kind: "activity", status: "imported", received_at: later},
        %{kind: "activity", status: "merged", received_at: later},
        %{kind: "sleep", status: "imported", received_at: ~U[2026-10-20 09:00:00.000000Z]},
        %{kind: "daily", status: "imported", received_at: later},
        %{kind: "weight", status: "ignored", received_at: later}
      ]

      card = ImportPolicy.card(imports, 1, seen)
      assert card.new_counts == %{"activity" => 2, "sleep" => 0, "weight" => 0}
      assert card.needs_confirmation == 1
      assert card.visible
      refute ImportPolicy.card([], 0, seen).visible
    end
  end
end
