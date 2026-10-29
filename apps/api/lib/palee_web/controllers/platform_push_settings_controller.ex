defmodule PaleeWeb.PlatformPushSettingsController do
  @moduledoc """
  ADR-218 / ADR-275: browser alerts for the whole Palee installation, for the
  platform team only. The server makes and keeps the key pair itself, so this
  shows status and the contact, and can replace the keys; it never returns or
  accepts a key.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Notifications
  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Platform"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, [json_render_error_v2: true] when action in [:update]

  @push_status_schema %Schema{
    type: :object,
    properties: %{
      enabled: %Schema{type: :boolean},
      source: %Schema{
        type: :string,
        enum: ["palee", "server", "none"],
        description: "palee: the pair the server made; server: WEB_PUSH_* env"
      },
      vapid_subject: %Schema{type: :string, nullable: true},
      subject_source: %Schema{type: :string, enum: ["palee", "server", "default"]},
      keys_created_at: %Schema{type: :string, format: :"date-time", nullable: true},
      device_count: %Schema{type: :integer, minimum: 0},
      last_sent_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [
      :device_count,
      :enabled,
      :keys_created_at,
      :last_sent_at,
      :source,
      :subject_source,
      :vapid_subject
    ]
  }

  operation(:show,
    summary: "Browser alerts for the installation: status, contact, devices (never a key)",
    responses: [ok: {"Push status", "application/json", @push_status_schema}]
  )

  def show(conn, _params), do: json(conn, status(conn))

  operation(:update,
    summary: "Save the contact push services use to reach the Palee team",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{vapid_subject: %Schema{type: :string, maxLength: 255}},
            required: [:vapid_subject]
          }
        }
      }
    },
    responses: [ok: {"Push status", "application/json", @push_status_schema}]
  )

  def update(conn, _params) do
    with :ok <- Notifications.save_push_contact(conn.body_params.vapid_subject) do
      json(conn, status(conn))
    end
  end

  operation(:rotate,
    summary: "Replace the key pair; every device subscribes again on its next visit",
    responses: [ok: {"Push status", "application/json", @push_status_schema}]
  )

  def rotate(conn, _params) do
    with {:ok, _removed} <- Notifications.replace_push_keys(vendor_id(conn)) do
      json(conn, status(conn))
    end
  end

  defp status(conn), do: Notifications.platform_push_status(vendor_id(conn))

  defp vendor_id(conn), do: conn.assigns.platform_context.user_id
end
