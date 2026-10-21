defmodule Palee.Web.VoiceLogControllerTest do
  @moduledoc """
  ADR-175 (P3-M13): voice logging end to end. Off by default (its own switch
  in the gym's AI settings, which needs the gym's key); a recording returns a
  transcript and a draft and saves nothing; the parse runs on the gym's key,
  both calls are metered under one operation; a failed parse still returns
  the transcript as the note; the daily cap counts recordings.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{AiUsage, Organizations, Repo}
  alias Palee.FakeSpeechTranscriber

  @key "sk-ant-test-0123456789abcdef"

  setup %{conn: conn} do
    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Voice Gym #{System.unique_integer([:positive])}"
      })

    person = fn role ->
      user = user_fixture()

      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })

      user
    end

    owner = person.(:owner)
    athlete = person.(:athlete)
    {:ok, owner_context} = Organizations.resolve_tenant_context(owner, organization.slug)
    {:ok, athlete_context} = Organizations.resolve_tenant_context(athlete, organization.slug)

    %{
      owner: owner,
      owner_context: owner_context,
      athlete: athlete,
      athlete_context: athlete_context,
      as: fn user -> put_bearer_token(conn, user) end,
      admin: "/api/org/#{organization.slug}/admin",
      voice: "/api/org/#{organization.slug}/me/training-log/voice"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp enable!(ctx, key \\ @key) do
    ctx.as.(ctx.owner)
    |> send_json("put", "#{ctx.admin}/ai-settings", %{api_key: key, voice_enabled: true})
    |> json_response(200)
  end

  defp clip, do: Base.encode64(:crypto.strong_rand_bytes(3_000))

  defp record(ctx, extra \\ %{}) do
    ctx.as.(ctx.athlete)
    |> send_json(
      "post",
      "#{ctx.voice}/drafts",
      Map.merge(
        %{audio_base64: clip(), mime_type: "audio/wav", duration_ms: 4_000, locale: "el"},
        extra
      )
    )
  end

  defp entry_count, do: Repo.aggregate("training_log_entries", :count)

  test "off by default: no recording, nothing called", ctx do
    assert %{"voice" => %{"available" => false, "enabled" => false, "max_seconds" => 60}} =
             ctx.as.(ctx.athlete) |> get(ctx.voice) |> json_response(200)

    assert %{"code" => "voice_log_unavailable"} = record(ctx) |> json_response(403)
    refute_received {:speech_transcriber_called, _clip, _options}

    # Scaling alone does not switch voice on.
    ctx.as.(ctx.owner)
    |> send_json("put", "#{ctx.admin}/ai-settings", %{api_key: @key, scaling_enabled: true})
    |> json_response(200)

    assert %{"code" => "voice_log_unavailable"} = record(ctx) |> json_response(403)
  end

  test "the switch needs a key and shows in the gym's settings", ctx do
    assert %{"code" => "api_key_required"} =
             ctx.as.(ctx.owner)
             |> send_json("put", "#{ctx.admin}/ai-settings", %{voice_enabled: true})
             |> json_response(422)

    assert %{"ai_settings" => %{"voice_enabled" => true, "scaling_enabled" => false}} =
             enable!(ctx)

    assert %{"voice" => %{"available" => true, "remaining_today" => 20, "daily_limit" => 20}} =
             ctx.as.(ctx.athlete) |> get(ctx.voice) |> json_response(200)
  end

  test "a recording becomes a draft; nothing is saved; both calls metered once", ctx do
    enable!(ctx)
    before = entry_count()

    body = record(ctx) |> json_response(200)

    assert body["transcript"] == FakeSpeechTranscriber.default_transcript()
    assert body["parsed"] == true

    assert %{
             "title" => "Squats και κωπηλατική",
             "duration_minutes" => 45,
             "perceived_effort" => 7,
             "exercises" => [
               %{
                 "name" => "Back Squat",
                 "sets" => 5,
                 "reps" => 5,
                 "load" => 100,
                 "load_unit" => "kg"
               },
               %{"name" => "Row", "load_unit" => nil}
             ]
           } = body["draft"]

    assert entry_count() == before

    assert_received {:speech_transcriber_called, clip, %{metering: transcribe_metering}}
    assert clip.mime_type == "audio/wav"
    assert clip.locale == "el"

    assert_received {:log_draft_parser_called, input, options}
    assert input == %{transcript: FakeSpeechTranscriber.default_transcript(), locale: "el"}
    assert options.api_key == @key
    assert options.model == "claude-sonnet-5-5"
    assert options.metering.feature == "voice_log"
    assert options.metering.user_id == ctx.athlete.id
    assert options.metering.operation_id == transcribe_metering.operation_id

    # Data minimisation: the parser sees no identity.
    refute inspect(input) =~ ctx.athlete.id

    assert %{"voice" => %{"remaining_today" => 19}} =
             ctx.as.(ctx.athlete) |> get(ctx.voice) |> json_response(200)

    assert %{key_status: "valid"} = AiUsage.get_settings(ctx.owner_context)
  end

  test "a failed parse keeps the transcript as the note; a rejected key is recorded", ctx do
    enable!(ctx, "rejected-key-0123456789abcdef")

    body = record(ctx) |> json_response(200)
    assert body["parsed"] == false
    assert body["draft"]["notes"] == FakeSpeechTranscriber.default_transcript()
    assert body["draft"]["exercises"] == []

    assert %{key_status: "rejected"} = AiUsage.get_settings(ctx.owner_context)

    assert %{"voice" => %{"available" => false}} =
             ctx.as.(ctx.athlete) |> get(ctx.voice) |> json_response(200)
  end

  test "unusable recordings, silence and transcription outages", ctx do
    enable!(ctx)

    assert %{"code" => "invalid_audio"} =
             record(ctx, %{mime_type: "image/png"}) |> json_response(422)

    assert %{"code" => "audio_too_long"} =
             record(ctx, %{duration_ms: 120_000}) |> json_response(422)

    Process.put(:fake_transcript, "   ")
    assert %{"code" => "no_speech"} = record(ctx) |> json_response(422)
    refute_received {:log_draft_parser_called, _input, _options}

    Process.put(:fake_transcript, {:error, :transcriber_not_configured})
    assert %{"code" => "transcription_unavailable"} = record(ctx) |> json_response(503)
  end

  test "the daily cap counts recordings per member", ctx do
    enable!(ctx)
    for _ <- 1..20, do: record(ctx) |> json_response(200)

    assert %{"code" => "voice_log_daily_limit"} = record(ctx) |> json_response(429)

    assert %{"voice" => %{"available" => false, "enabled" => true, "remaining_today" => 0}} =
             ctx.as.(ctx.athlete) |> get(ctx.voice) |> json_response(200)
  end
end
