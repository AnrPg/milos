defmodule MilosTrainingWeb.PlatformOrganizationController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    ChangeOrganizationLifecycle,
    ChangeOrganizationSettings,
    ListProvisionedOrganizations,
    ProvisionOrganization
  }

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Platform Organizations"])
  security([%{"bearerAuth" => []}])

  @organization_id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  @organization_schema %Schema{
    type: :object,
    additionalProperties: true
  }

  operation(:index,
    summary: "List provisioned organizations",
    responses: [ok: {"Organizations", "application/json", %Schema{type: :object}}]
  )

  operation(:create,
    summary: "Provision an organization and one-time initial owner invitation",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              name: %Schema{type: :string, minLength: 2, maxLength: 120},
              slug: %Schema{type: :string},
              timezone: %Schema{type: :string},
              default_locale: %Schema{type: :string},
              invitation_lifetime_seconds: %Schema{type: :integer},
              initial_owner_email: %Schema{type: :string},
              brand_name: %Schema{type: :string},
              brand_logo_url: %Schema{type: :string},
              brand_primary_color: %Schema{type: :string}
            },
            required: [:name]
          }
        }
      }
    },
    responses: [created: {"Provisioned organization", "application/json", @organization_schema}]
  )

  operation(:lifecycle,
    summary: "Change organization lifecycle state",
    parameters: [@organization_id],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              status: %Schema{type: :string, enum: ["active", "suspended", "archived"]}
            },
            required: [:status]
          }
        }
      }
    },
    responses: [ok: {"Organization", "application/json", @organization_schema}]
  )

  operation(:settings,
    summary: "Update organization branding, locale, timezone, and invitation lifetime",
    parameters: [@organization_id],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: %Schema{type: :object}}}
    },
    responses: [ok: {"Organization settings", "application/json", @organization_schema}]
  )

  def index(conn, _params) do
    with {:ok, organizations} <-
           ListProvisionedOrganizations.call(conn.assigns.platform_context) do
      json(conn, %{organizations: Enum.map(organizations, &serialize_entry/1)})
    end
  end

  def create(conn, _params) do
    with {:ok, result} <-
           ProvisionOrganization.call(conn.assigns.platform_context, conn.body_params) do
      conn
      |> put_status(:created)
      |> json(%{
        organization: serialize_organization(result.organization),
        settings: serialize_settings(result.settings),
        initial_owner_invitation: %{
          token: result.initial_owner_token,
          expires_at: result.invitation.expires_at,
          role: result.invitation.role
        },
        canonical_path: "/org/#{result.organization.slug}"
      })
    end
  end

  def lifecycle(conn, %{"id" => organization_id}) do
    with {:ok, organization} <-
           ChangeOrganizationLifecycle.call(
             conn.assigns.platform_context,
             organization_id,
             conn.body_params["status"]
           ) do
      json(conn, %{organization: serialize_organization(organization)})
    end
  end

  def settings(conn, %{"id" => organization_id}) do
    with {:ok, settings} <-
           ChangeOrganizationSettings.call(
             conn.assigns.platform_context,
             organization_id,
             conn.body_params
           ) do
      json(conn, %{settings: serialize_settings(settings)})
    end
  end

  defp serialize_entry(%{organization: organization, settings: settings}) do
    %{
      organization: serialize_organization(organization),
      settings: serialize_settings(settings),
      canonical_path: "/org/#{organization.slug}"
    }
  end

  defp serialize_organization(organization) do
    %{
      id: organization.id,
      slug: organization.slug,
      name: organization.name,
      status: organization.status,
      inserted_at: organization.inserted_at,
      updated_at: organization.updated_at
    }
  end

  defp serialize_settings(nil), do: nil

  defp serialize_settings(settings) do
    %{
      organization_id: settings.organization_id,
      timezone: settings.timezone,
      default_locale: settings.default_locale,
      invitation_lifetime_seconds: settings.invitation_lifetime_seconds,
      brand_name: settings.brand_name,
      brand_logo_url: settings.brand_logo_url,
      brand_primary_color: settings.brand_primary_color,
      settings: settings.settings
    }
  end
end
