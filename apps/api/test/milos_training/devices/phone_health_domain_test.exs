defmodule MilosTraining.Devices.PhoneHealthDomainTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Devices.Domain.{
    Catalog,
    ConnectionPolicy,
    ImportPolicy,
    PhoneHealthSample,
    SummaryReader
  }

  describe "PhoneHealthSample" do
    test "a workout keeps the wearer's offset, sport and numbers" do
      assert {:ok, activity} =
               PhoneHealthSample.activity(%{
                 "id" => "A1",
                 "type" => "TRADITIONAL_STRENGTH_TRAINING",
                 "title" => "  Upper body  ",
                 "start" => "2026-10-20T18:30:00+03:00",
                 "end" => "2026-10-20T19:25:30+03:00",
                 "distance_m" => 0,
                 "avg_hr" => 128.6,
                 "max_hr" => 400
               })

      assert activity.provider_id == "A1"
      assert activity.sport == "strength"
      assert activity.title == "Upper body"
      assert activity.started_at == ~U[2026-10-20 15:30:00Z]
      assert activity.started_tz == "Etc/GMT-3"
      assert activity.local_date == ~D[2026-10-20]
      assert activity.duration_seconds == 3330
      assert activity.distance_meters == nil
      assert activity.avg_heart_rate == 129
      assert activity.max_heart_rate == nil
      assert activity.calories == nil
    end

    test "a workout without a sane span is refused" do
      assert {:error, :missing_start} = PhoneHealthSample.activity(%{"id" => "x"})

      assert {:error, :missing_duration} =
               PhoneHealthSample.activity(%{
                 "id" => "x",
                 "start" => "2026-10-20T10:00:00Z",
                 "end" => "2026-10-21T11:00:00Z"
               })
    end

    test "a night lands on the day it ends, in local time" do
      assert {:ok, night} =
               PhoneHealthSample.sleep(%{
                 "id" => "2026-10-20",
                 "start" => "2026-10-19T23:40:00+03:00",
                 "end" => "2026-10-20T00:20:00Z"
               })

      assert night.on == ~D[2026-10-20]
      assert night.tz == "UTC"
      assert night.quality == nil

      assert {:error, :missing_duration} =
               PhoneHealthSample.sleep(%{
                 "id" => "n",
                 "start" => "2026-10-20T10:00:00Z",
                 "end" => "2026-10-20T10:10:00Z"
               })
    end

    test "weights and daily numbers are bounded" do
      assert {:ok, %{metrics: %{"weight" => 71.84}, on: ~D[2026-10-20]}} =
               PhoneHealthSample.weight(%{
                 "id" => "w",
                 "at" => "2026-10-20T07:00:00+02:00",
                 "kg" => 71.8401
               })

      assert {:error, :missing_weight} =
               PhoneHealthSample.weight(%{"id" => "w", "at" => "2026-10-20T07:00:00Z", "kg" => 2})

      assert {:ok, %{resting_heart_rate: 52, provider_id: "2026-10-20"}} =
               PhoneHealthSample.daily(%{"date" => "2026-10-20", "resting_hr" => 51.7})

      assert {:error, :missing_resting_heart_rate} =
               PhoneHealthSample.daily(%{"date" => "2026-10-20", "resting_hr" => 250})

      assert {:ok, %{steps: 8000}} =
               PhoneHealthSample.steps(%{"date" => "2026-10-20", "steps" => 8000})

      assert {:error, :missing_date} = PhoneHealthSample.steps(%{"date" => "x", "steps" => 1})
    end

    test "a batch splits a day into its resting heart rate and its steps" do
      assert {:ok, batches} =
               PhoneHealthSample.batches(%{
                 "activities" => [%{"id" => "a"}],
                 "dailies" => [
                   %{"date" => "2026-10-20", "resting_hr" => 50, "steps" => 10},
                   %{"date" => "2026-10-21", "steps" => 20},
                   "junk"
                 ]
               })

      assert [{"activity", [_]}, {"daily", [_]}, {"steps", [_, _]}] = batches

      too_many = for _ <- 1..501, do: %{"id" => "a"}

      assert {:error, :phone_health_batch_too_large} =
               PhoneHealthSample.batches(%{"activities" => too_many})

      assert {:error, :invalid_phone_health_batch} = PhoneHealthSample.batches(nil)
    end

    test "ids and the audit copy" do
      assert PhoneHealthSample.provider_id("steps", %{"date" => "2026-10-20"}) == "2026-10-20"
      assert PhoneHealthSample.provider_id("activity", %{"id" => ""}) == nil

      assert PhoneHealthSample.trim("weight", %{"id" => "w", "kg" => 70, "device" => "x"}) ==
               %{"id" => "w", "kg" => 70}
    end
  end

  describe "SummaryReader" do
    test "one reading per kind, whoever sent it" do
      assert {:ok, %{sport: "run"}} =
               SummaryReader.read("health_connect", "activity", %{
                 "id" => "a",
                 "type" => "RUNNING",
                 "start" => "2026-10-20T10:00:00Z",
                 "end" => "2026-10-20T10:30:00Z"
               })

      assert {:ok, %{sport: "run"}} =
               SummaryReader.read("garmin", "activity", %{
                 "summaryId" => "g",
                 "activityType" => "RUNNING",
                 "startTimeInSeconds" => 1_790_000_000,
                 "durationInSeconds" => 600
               })

      assert {:error, :unsupported_kind} = SummaryReader.read("garmin", "steps", %{})
      assert {:error, :unknown_provider} = SummaryReader.read("fitbit", "activity", %{})
      assert SummaryReader.provider_id("garmin", "activity", %{"summaryId" => 7}) == "7"
      assert SummaryReader.provider_id("apple_health", "daily", %{"date" => "2026-10-20"})
      assert SummaryReader.provider_id("fitbit", "daily", %{}) == nil
    end
  end

  describe "Catalog" do
    test "the phone offers steps; Garmin keeps its four choices" do
      assert "steps" in Catalog.pref_keys("apple_health")
      refute "steps" in Catalog.pref_keys("garmin")
      refute Map.has_key?(Catalog.default_prefs(), "steps")

      assert {:error, :invalid_sync_prefs} =
               Catalog.merge_prefs("garmin", %{}, %{"steps" => true})

      assert {:ok, %{"steps" => false}} =
               Catalog.merge_prefs("health_connect", %{}, %{steps: false})
    end

    test "steps are health data on a phone, unknown to Garmin" do
      workouts = %{
        "activities" => true,
        "sleep" => false,
        "weight" => false,
        "resting_hr" => false
      }

      refute Catalog.health_data?("garmin", workouts)
      assert Catalog.health_data?("apple_health", workouts)
      refute Catalog.health_data?("apple_health", Map.put(workouts, "steps", false))
    end

    test "nights and day numbers are replaceable, samples are not" do
      assert Catalog.replaceable_kind?("steps")
      assert Catalog.replaceable_kind?("sleep")
      refute Catalog.replaceable_kind?("activity")
      refute Catalog.replaceable_kind?("weight")
    end
  end

  describe "ImportPolicy across devices" do
    test "another device's night or weigh-in wins; the same device's is replaced" do
      garmin = %{id: "g", kind: "sleep", source: "garmin", value: %{}}
      phone = %{id: "p", kind: "sleep", source: "apple_health", value: %{}}

      assert {:other_device, "g"} = ImportPolicy.sleep_decision([garmin], "apple_health")
      assert :import = ImportPolicy.sleep_decision([phone], "apple_health")

      assert {:other_device, "s"} =
               ImportPolicy.weight_decision(
                 [%{id: "s", source: "garmin", metrics: %{"weight" => 70}}],
                 "health_connect"
               )
    end

    test "an overlapping workout from another device is a duplicate" do
      watch = %{
        id: "w",
        provider: "garmin",
        started_at: ~U[2026-10-20 07:00:00Z],
        duration_seconds: 1800
      }

      run = %{started_at: ~U[2026-10-20 07:02:00Z], duration_seconds: 1700}
      later = %{started_at: ~U[2026-10-20 12:00:00Z], duration_seconds: 1700}

      assert ImportPolicy.other_device_activity(run, [watch], "apple_health") == "w"
      assert ImportPolicy.other_device_activity(run, [watch], "garmin") == nil
      assert ImportPolicy.other_device_activity(later, [watch], "apple_health") == nil
    end
  end

  describe "ConnectionPolicy" do
    test "the phone reads 30 days back first, then two days before the last sync" do
      connected = ~U[2026-10-20 10:00:00Z]

      assert ConnectionPolicy.phone_read_from(%{connected_at: connected, last_synced_at: nil}) ==
               ~U[2026-09-20 10:00:00Z]

      assert ConnectionPolicy.phone_read_from(%{
               connected_at: connected,
               last_synced_at: ~U[2026-10-21 08:00:00Z]
             }) == ~U[2026-10-19 08:00:00Z]

      assert ConnectionPolicy.phone_read_from(nil) == nil
    end
  end
end
