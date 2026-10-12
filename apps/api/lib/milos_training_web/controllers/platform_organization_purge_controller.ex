defmodule MilosTrainingWeb.PlatformOrganizationPurgeController do
  @moduledoc """
  ADR-099 reviewed tenant export/purge workflow for vendors:
  request -> export (job) -> retention review -> typed approval -> purge (job).
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    ApproveOrganizationPurge,
    CancelOrganizationPurge,
    GetOrganizationPurgeStatus,
    ListOrganizationPurges,
    RequestOrganizationPurge,
    ResumeOrganizationPurge
  }

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Platform Organization Purges"])
  security([%{"bearerAuth" => []}])

  @organization_id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  @statuses ~w(requested exporting exported approved purging completed failed cancelled)

  @retention_entry_schema %Schema{
    type: :object,
    properties: %{
      context: %Schema{type: :string},
      disposition: %Schema{type: :string, enum: ["purge", "retain", "retain_anonymized"]},
      retain_years: %Schema{type: :integer, nullable: true},
      retained_until: %Schema{type: :string, format: :date, nullable: true},
      basis: %Schema{type: :string},
      record_count: %Schema{type: :integer},
      resources: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          properties: %{resource: %Schema{type: :string}, count: %Schema{type: :integer}},
          required: [:resource, :count]
        }
      }
    },
    required: [:context, :disposition, :record_count, :resources]
  }

  @purge_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      organization_id: %Schema{type: :string, format: :uuid},
      organization_slug: %Schema{type: :string},
      status: %Schema{type: :string, enum: @statuses},
      failed_stage: %Schema{type: :string, enum: ["export", "purge"], nullable: true},
      failure_reason: %Schema{type: :string, nullable: true},
      requested_by_user_id: %Schema{type: :string, format: :uuid},
      requested_at: %Schema{type: :string, format: :"date-time"},
      export_completed_at: %Schema{type: :string, format: :"date-time", nullable: true},
      export_byte_size: %Schema{type: :integer, nullable: true},
      export_sha256: %Schema{type: :string, nullable: true},
      retention_review: %Schema{type: :array, items: @retention_entry_schema},
      approved_by_user_id: %Schema{type: :string, format: :uuid, nullable: true},
      approval_mode: %Schema{
        type: :string,
        enum: ["second_vendor", "typed_confirmation"],
        nullable: true
      },
      approved_at: %Schema{type: :string, format: :"date-time", nullable: true},
      purge_started_at: %Schema{type: :string, format: :"date-time", nullable: true},
      steps: %Schema{type: :object, additionalProperties: true},
      completed_at: %Schema{type: :string, format: :"date-time", nullable: true},
      cancelled_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:id, :organization_id, :organization_slug, :status, :requested_at]
  }

  @purge_response %Schema{
    type: :object,
    properties: %{purge: @purge_schema},
    required: [:purge]
  }

  operation(:create,
    summary: "Request a reviewed tenant purge (suspends the organization and starts the export)",
    parameters: [@organization_id],
    responses: [
      created: {"Purge request", "application/json", @purge_response},
      conflict: {"An open purge already exists", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:show,
    summary: "Latest purge status, retention review, and signed export link",
    parameters: [@organization_id],
    responses: [
      ok:
        {"Purge status", "application/json",
         %Schema{
           type: :object,
           properties: %{
             purge: @purge_schema,
             export_download_url: %Schema{type: :string, nullable: true}
           },
           required: [:purge, :export_download_url]
         }},
      not_found: {"No purge requested", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:approve,
    summary: "Approve an exported purge by retyping the organization slug",
    parameters: [@organization_id],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{confirmation: %Schema{type: :string}},
            required: [:confirmation]
          }
        }
      }
    },
    responses: [
      ok: {"Approved purge", "application/json", @purge_response},
      unprocessable_entity: {"Confirmation mismatch", "application/json", %Schema{type: :object}},
      conflict: {"Purge is not awaiting approval", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:cancel,
    summary: "Cancel a purge that has not been approved and delete its export",
    parameters: [@organization_id],
    responses: [ok: {"Cancelled purge", "application/json", @purge_response}]
  )

  operation(:resume,
    summary: "Re-enqueue the export or purge stage of an open purge after a failure",
    parameters: [@organization_id],
    responses: [ok: {"Resumed purge", "application/json", @purge_response}]
  )

  operation(:index,
    summary: "Recent purge records (audit trail that survives purged organizations)",
    responses: [
      ok:
        {"Purges", "application/json",
         %Schema{
           type: :object,
           properties: %{purges: %Schema{type: :array, items: @purge_schema}},
           required: [:purges]
         }}
    ]
  )

  def create(conn, %{"id" => organization_id}) do
    with {:ok, purge} <-
           RequestOrganizationPurge.call(conn.assigns.platform_context, organization_id) do
      conn
      |> put_status(:created)
      |> json(%{purge: serialize(purge)})
    end
  end

  def show(conn, %{"id" => organization_id}) do
    with {:ok, %{purge: purge, export_download_url: url}} <-
           GetOrganizationPurgeStatus.call(conn.assigns.platform_context, organization_id) do
      json(conn, %{purge: serialize(purge), export_download_url: url})
    end
  end

  def approve(conn, %{"id" => organization_id}) do
    with {:ok, purge} <-
           ApproveOrganizationPurge.call(
             conn.assigns.platform_context,
             organization_id,
             conn.body_params
           ) do
      json(conn, %{purge: serialize(purge)})
    end
  end

  def cancel(conn, %{"id" => organization_id}) do
    with {:ok, purge} <-
           CancelOrganizationPurge.call(conn.assigns.platform_context, organization_id) do
      json(conn, %{purge: serialize(purge)})
    end
  end

  def resume(conn, %{"id" => organization_id}) do
    with {:ok, purge} <-
           ResumeOrganizationPurge.call(conn.assigns.platform_context, organization_id) do
      json(conn, %{purge: serialize(purge)})
    end
  end

  def index(conn, _params) do
    with {:ok, purges} <- ListOrganizationPurges.call(conn.assigns.platform_context) do
      json(conn, %{purges: Enum.map(purges, &serialize/1)})
    end
  end

  defp serialize(purge) do
    %{
      id: purge.id,
      organization_id: purge.organization_id,
      organization_slug: purge.organization_slug,
      status: purge.status,
      failed_stage: purge.failed_stage,
      failure_reason: purge.failure_reason,
      requested_by_user_id: purge.requested_by_user_id,
      requested_at: purge.requested_at,
      export_completed_at: purge.export_completed_at,
      export_byte_size: purge.export_byte_size,
      export_sha256: purge.export_sha256,
      retention_review: purge.retention_review,
      approved_by_user_id: purge.approved_by_user_id,
      approval_mode: purge.approval_mode,
      approved_at: purge.approved_at,
      purge_started_at: purge.purge_started_at,
      steps: purge.steps,
      completed_at: purge.completed_at,
      cancelled_at: purge.cancelled_at
    }
  end
end
