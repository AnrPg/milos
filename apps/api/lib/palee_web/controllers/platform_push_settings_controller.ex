defmodule PaleeWeb.PlatformPushSettingsController do
  @moduledoc """
  ADR-218: the Web Push (VAPID) keys are one setting for the whole Palee
  installation, so only the platform team edits them. Gym owners never see them.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Notifications
  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Platform"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, [json_render_error_v2: true] when action in [:update]

  @push_settings_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, nullable: true},
      enabled: %Schema{type: :boolean},
      vapid_public_key: %Schema{type: :string, nullable: true},
      vapid_private_key_configured: %Schema{type: :boolean},
      vapid_subject: %Schema{type: :string, nullable: true},
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:enabled, :vapid_private_key_configured]
  }

  operation(:show,
    summary: "The installation's Web Push settings (never the private key)",
    responses: [ok: {"Push settings", "application/json", @push_settings_schema}]
  )

  def show(conn, _params), do: json(conn, Notifications.get_push_settings())

  operation(:update,
    summary: "Save or replace the installation's Web Push keys and contact",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              vapid_public_key: %Schema{type: :string, nullable: true},
              vapid_private_key: %Schema{type: :string, nullable: true},
              vapid_subject: %Schema{type: :string, nullable: true}
            },
            required: []
          }
        }
      }
    },
    responses: [ok: {"Push settings", "application/json", @push_settings_schema}]
  )

  def update(conn, _params) do
    params =
      conn.body_params
      |> Map.take([:vapid_public_key, :vapid_private_key, :vapid_subject])

    with {:ok, settings} <- Notifications.update_push_settings(params) do
      json(conn, settings)
    end
  end
end
