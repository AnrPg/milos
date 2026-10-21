defmodule MilosTrainingWeb.AdminAiSettingsController do
  @moduledoc """
  The gym's AI settings (ADR-174): scaling suggestions on or off (off by
  default), the gym's own key (write-only: only «set», its last four
  characters and whether the provider rejected it come back), an optional
  model, and this month's metered usage.
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.GymAiSettings
  alias MilosTrainingWeb.Schemas.Scaling, as: ScalingSchemas
  alias OpenApiSpex.Schema

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Settings"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @error %Schema{type: :object, additionalProperties: true}

  operation(:show,
    summary: "The gym's AI settings and this month's usage",
    responses: [ok: {"AI settings", "application/json", ScalingSchemas.ai_settings_response()}]
  )

  def show(conn, _params) do
    json(conn, %{ai_settings: GymAiSettings.get(conn.assigns.tenant_context)})
  end

  operation(:update,
    summary: "Update the gym's AI settings",
    request_body: ScalingSchemas.body(ScalingSchemas.ai_settings_request()),
    responses: [
      ok: {"AI settings", "application/json", ScalingSchemas.ai_settings_response()},
      unprocessable_entity: {"Invalid settings", "application/json", @error}
    ]
  )

  def update(conn, _params) do
    params =
      Map.take(conn.body_params, [:scaling_enabled, :voice_enabled, :api_key, :remove_key, :model])

    case GymAiSettings.update(conn.assigns.tenant_context, params) do
      {:ok, settings} ->
        json(conn, %{ai_settings: settings})

      {:error, reason}
      when reason in [
             :api_key_required,
             :invalid_api_key,
             :invalid_model,
             :invalid_scaling_enabled,
             :invalid_voice_enabled,
             :bad_request
           ] ->
        code = Atom.to_string(reason)
        conn |> put_status(:unprocessable_entity) |> json(%{code: code, error: code})

      {:error, _reason} = error ->
        error
    end
  end
end
