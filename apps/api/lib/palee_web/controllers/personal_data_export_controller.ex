defmodule PaleeWeb.PersonalDataExportController do
  @moduledoc """
  ADR-267: "Download my data" (GDPR articles 15 and 20). The signed-in
  profile asks for a copy of its own data; it is built in the background and
  offered here with short-lived download links, and an email says when it is
  ready.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Palee.Application.PersonalDataExports

  action_fallback PaleeWeb.FallbackController

  tags(["Personal data"])

  @file_schema %Schema{
    type: :object,
    nullable: true,
    description: "The ZIP of JSON files, while it is kept (status ready)",
    properties: %{
      name: %Schema{type: :string},
      bytes: %Schema{type: :integer},
      sha256: %Schema{type: :string},
      download_url: %Schema{
        type: :string,
        nullable: true,
        description: "Short-lived presigned link, made afresh on every request"
      }
    },
    required: [:bytes, :download_url, :name, :sha256]
  }

  @export_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      status: %Schema{type: :string, enum: ["pending", "ready", "failed", "expired"]},
      record_count: %Schema{type: :integer, nullable: true},
      requested_at: %Schema{type: :string, format: :"date-time"},
      completed_at: %Schema{type: :string, format: :"date-time", nullable: true},
      expires_at: %Schema{type: :string, format: :"date-time", nullable: true},
      file: @file_schema
    },
    required: [:id, :requested_at, :status]
  }

  @error_schema %Schema{
    type: :object,
    properties: %{
      code: %Schema{type: :string},
      error: %Schema{type: :string},
      retry_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:code, :error]
  }

  operation(:index,
    summary: "Your data exports, newest first, with short-lived download links",
    responses: [
      ok:
        {"Exports", "application/json",
         %Schema{
           type: :object,
           properties: %{exports: %Schema{type: :array, items: @export_schema}},
           required: [:exports]
         }}
    ]
  )

  def index(conn, _params) do
    with {:ok, exports} <- PersonalDataExports.list(conn.assigns.user_context) do
      json(conn, %{exports: exports})
    end
  end

  operation(:create,
    summary: "Ask for a copy of all your data (one ZIP of JSON files)",
    description:
      "One request at a time and one a day. The file is built in the background; an email says when it is ready.",
    responses: [
      accepted:
        {"Requested", "application/json",
         %Schema{
           type: :object,
           properties: %{export: @export_schema},
           required: [:export]
         }},
      conflict: {"An export is being prepared", "application/json", @error_schema},
      too_many_requests: {"Asked less than a day ago", "application/json", @error_schema}
    ]
  )

  def create(conn, _params) do
    with {:ok, export} <- PersonalDataExports.request(conn.assigns.user_context) do
      conn
      |> put_status(:accepted)
      |> json(%{export: export})
    end
  end
end
