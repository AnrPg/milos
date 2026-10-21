defmodule Palee.VoiceLog.DomainTest do
  @moduledoc "ADR-175: the pure rules of voice logging (clip checks, draft validation, daily cap)."

  use ExUnit.Case, async: true

  alias Palee.AiUsage.Domain.AiSettingsPolicy
  alias Palee.VoiceLog.Domain.{Clip, Draft, VoicePolicy}

  describe "Clip.build/3" do
    test "accepts a WAV clip and keeps it in memory only" do
      bytes = :crypto.strong_rand_bytes(4_000)

      assert {:ok, %{audio: ^bytes, mime_type: "audio/wav"}} =
               Clip.build(Base.encode64(bytes), "audio/x-wav", 4_000)

      assert {:ok, %{mime_type: "audio/mp4"}} =
               Clip.build(Base.encode64(bytes), "audio/mp4;codecs=mp4a.40.2", nil)
    end

    test "rejects unknown types, garbage, tiny and oversized clips" do
      bytes = :crypto.strong_rand_bytes(4_000)
      assert {:error, :invalid_audio} = Clip.build(Base.encode64(bytes), "video/mp4", nil)
      assert {:error, :invalid_audio} = Clip.build("not base64 !!", "audio/wav", nil)
      assert {:error, :invalid_audio} = Clip.build(Base.encode64("tiny"), "audio/wav", nil)
      assert {:error, :invalid_audio} = Clip.build(nil, "audio/wav", nil)
      assert {:error, :audio_too_long} = Clip.build(Base.encode64(bytes), "audio/wav", 90_000)

      big = :binary.copy(<<0>>, Clip.max_bytes() + 10)
      assert {:error, :audio_too_long} = Clip.build(Base.encode64(big), "audio/wav", nil)
    end
  end

  describe "Draft.normalize/1" do
    test "keeps valid fields, drops nameless exercises, nulls out-of-range values" do
      raw = %{
        "title" => "  Fran \n ",
        "duration_minutes" => 12,
        "perceived_effort" => 11,
        "days_ago" => 1,
        "notes" => "",
        "exercises" => [
          %{"name" => "Thruster", "sets" => 3, "reps" => 21, "load" => 42.5, "load_unit" => "kg"},
          %{"name" => "Pull-up", "sets" => 3, "reps" => 21.0, "load" => nil, "load_unit" => "kg"},
          %{"name" => "", "sets" => 1},
          %{"name" => "Deadlift", "load" => 225, "load_unit" => "stone", "reps" => -1},
          "garbage"
        ]
      }

      assert {:ok, draft} = Draft.normalize(raw)
      assert draft.title == "Fran"
      assert draft.duration_minutes == 12
      assert draft.perceived_effort == nil
      assert draft.days_ago == 1
      assert draft.notes == nil

      assert [
               %{name: "Thruster", sets: 3, reps: 21, load: 42.5, load_unit: "kg"},
               %{name: "Pull-up", reps: 21, load: nil, load_unit: nil},
               %{name: "Deadlift", reps: nil, load: 225, load_unit: "kg"}
             ] = draft.exercises
    end

    test "an answer without an exercise list is invalid; a missing list is empty" do
      assert {:error, :parser_invalid_response} = Draft.normalize(%{"exercises" => "x"})
      assert {:error, :parser_invalid_response} = Draft.normalize("text")
      assert {:ok, %{exercises: []}} = Draft.normalize(%{"title" => "Run"})
    end

    test "the fallback keeps the transcript as the note" do
      assert %{notes: "Τρέξιμο 5 χλμ", exercises: [], title: nil} =
               Draft.from_transcript("  Τρέξιμο   5 χλμ ")

      assert Draft.transcript("   ") == nil
    end
  end

  describe "VoicePolicy" do
    test "off, out of drafts, or ready" do
      assert {:error, :voice_log_unavailable} = VoicePolicy.check(false, 5)
      assert {:error, :voice_log_daily_limit} = VoicePolicy.check(true, 0)
      assert :ok = VoicePolicy.check(true, 1)
      assert VoicePolicy.remaining(25) == 0
      assert VoicePolicy.remaining(3, 20) == 17

      assert VoicePolicy.day_start(~U[2026-10-21 17:45:12.123456Z]) ==
               ~U[2026-10-21 00:00:00Z]
    end

    test "the gym's switch: off by default, needs a key, off again when the key goes" do
      refute AiSettingsPolicy.voice_ready?(nil)

      refute AiSettingsPolicy.voice_ready?(%{
               voice_enabled: true,
               api_key: nil,
               key_status: "unknown"
             })

      refute AiSettingsPolicy.voice_ready?(%{
               voice_enabled: true,
               api_key: "k",
               key_status: "rejected"
             })

      assert AiSettingsPolicy.voice_ready?(%{
               voice_enabled: true,
               api_key: "k",
               key_status: "valid"
             })

      assert {:error, :api_key_required} =
               AiSettingsPolicy.update_changes(nil, %{voice_enabled: true}, nil)

      assert {:error, :invalid_voice_enabled} =
               AiSettingsPolicy.update_changes(nil, %{"voice_enabled" => "yes"}, nil)

      assert {:ok, %{voice_enabled: false, scaling_enabled: false}} =
               AiSettingsPolicy.update_changes(%{api_key: "k"}, %{remove_key: true}, nil)

      assert %{voice_enabled: false} = AiSettingsPolicy.public(nil, "m")
    end
  end
end
