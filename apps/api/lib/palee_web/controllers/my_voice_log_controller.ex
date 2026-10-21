defmodule PaleeWeb.MyVoiceLogController do
  @moduledoc """
  Voice logging (ADR-175): whether the member may record, and one recording
  → transcript + draft training-log entry. Nothing is saved: the member
  reviews the draft in the log form and saves it as a normal entry. The
  audio is held in memory for this request only.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.VoiceLogDrafts
  alias PaleeWeb.Schemas.VoiceLog, as: VoiceLogSchemas
  alias OpenApiSpex.Schema

  action_fallback PaleeWeb.FallbackController

  tags(["Training Log"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @error %Schema{type: :object, additionalProperties: true}

  @statuses %{
    voice_log_unavailable: :forbidden,
    voice_log_daily_limit: :too_many_requests,
    invalid_audio: :unprocessable_entity,
    audio_too_long: :unprocessable_entity,
    no_speech: :unprocessable_entity,
    transcription_unavailable: :service_unavailable
  }

  operation(:show,
    summary: "Whether the current user may log a workout by voice",
    responses: [ok: {"Availability", "application/json", VoiceLogSchemas.availability_response()}]
  )

  def show(conn, _params) do
    json(conn, %{voice: VoiceLogDrafts.availability(conn.assigns.tenant_context)})
  end

  operation(:create,
    summary: "Transcribe one recording into a draft training-log entry (nothing is saved)",
    request_body: VoiceLogSchemas.body(VoiceLogSchemas.draft_request()),
    responses: [
      ok: {"Draft", "application/json", VoiceLogSchemas.draft_response()},
      forbidden: {"Voice logging is off", "application/json", @error},
      unprocessable_entity: {"Unusable recording", "application/json", @error},
      too_many_requests: {"Daily limit reached", "application/json", @error},
      service_unavailable: {"Transcription unavailable", "application/json", @error}
    ]
  )

  def create(conn, _params) do
    params = Map.take(conn.body_params, [:audio_base64, :mime_type, :duration_ms, :locale])

    case VoiceLogDrafts.draft(conn.assigns.tenant_context, params) do
      {:ok, result} ->
        json(conn, result)

      {:error, reason} when is_map_key(@statuses, reason) ->
        code = Atom.to_string(reason)
        conn |> put_status(Map.fetch!(@statuses, reason)) |> json(%{code: code, error: code})

      {:error, _reason} = error ->
        error
    end
  end
end
