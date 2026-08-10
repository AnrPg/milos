defmodule MilosTrainingWeb.PlatformOrganizationController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    ChangeOrganizationLifecycle,
    ChangeOrganizationSettings,
    DeleteOrganization,
    IssuePlatformOrganizationInvitation,
    ListPlatformOrganizationAccess,
    ListProvisionedOrganizations,
    ProvisionOrganization,
    RenameOrganization,
    SendOwnerInvitationEmail,
    UpdatePlatformOrganizationMembershipRole
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
            required: [:name, :initial_owner_email]
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

  operation(:rename,
    summary: "Rename an organization's canonical display name",
    parameters: [@organization_id],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{name: %Schema{type: :string, minLength: 2, maxLength: 120}},
            required: [:name]
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

  operation(:delete,
    summary: "Permanently delete an organization",
    parameters: [@organization_id],
    responses: [no_content: "Organization permanently deleted"]
  )

  operation(:access,
    summary: "List tenant memberships for platform access management",
    parameters: [@organization_id],
    responses: [ok: {"Organization access", "application/json", @organization_schema}]
  )

  operation(:invite,
    summary: "Issue a tenant invitation from the platform console",
    parameters: [@organization_id],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              role: %Schema{type: :string, enum: ~w(owner admin coach member athlete)},
              lifetime_seconds: %Schema{type: :integer, minimum: 300, maximum: 604_800},
              intended_email: %Schema{type: :string}
            },
            required: [:role]
          }
        }
      }
    },
    responses: [created: {"Invitation token", "application/json", @organization_schema}]
  )

  operation(:invitation_email,
    summary: "Email an already-issued invitation's setup link to its recipient",
    parameters: [@organization_id],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              email: %Schema{type: :string},
              token: %Schema{type: :string}
            },
            required: [:email, :token]
          }
        }
      }
    },
    responses: [no_content: "Invitation email sent"]
  )

  operation(:membership_role,
    summary: "Update a tenant membership role from the platform console",
    parameters: [
      @organization_id,
      %Parameter{
        name: :membership_id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              role: %Schema{type: :string, enum: ~w(owner admin coach member athlete)}
            },
            required: [:role]
          }
        }
      }
    },
    responses: [ok: {"Membership", "application/json", @organization_schema}]
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

  def rename(conn, %{"id" => organization_id}) do
    with {:ok, organization} <-
           RenameOrganization.call(
             conn.assigns.platform_context,
             organization_id,
             conn.body_params["name"]
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

  def delete(conn, %{"id" => organization_id}) do
    with {:ok, _organization} <-
           DeleteOrganization.call(conn.assigns.platform_context, organization_id) do
      send_resp(conn, :no_content, "")
    end
  end

  def access(conn, %{"id" => organization_id}) do
    with {:ok, result} <-
           ListPlatformOrganizationAccess.call(conn.assigns.platform_context, organization_id) do
      json(conn, %{
        organization: serialize_organization(result.organization),
        memberships: Enum.map(result.memberships, &serialize_access_membership/1)
      })
    end
  end

  def invite(conn, %{"id" => organization_id}) do
    with {:ok, result} <-
           IssuePlatformOrganizationInvitation.call(
             conn.assigns.platform_context,
             organization_id,
             conn.body_params
           ) do
      conn
      |> put_status(:created)
      |> json(%{
        invitation: %{
          token: result.token,
          expires_at: result.invitation.expires_at,
          role: result.invitation.role
        }
      })
    end
  end

  def invitation_email(conn, %{"id" => organization_id}) do
    with {:ok, _event} <-
           SendOwnerInvitationEmail.call(
             conn.assigns.platform_context,
             organization_id,
             conn.body_params
           ) do
      send_resp(conn, :no_content, "")
    end
  end

  def membership_role(conn, %{"id" => organization_id, "membership_id" => membership_id}) do
    with {:ok, membership} <-
           UpdatePlatformOrganizationMembershipRole.call(
             conn.assigns.platform_context,
             organization_id,
             membership_id,
             conn.body_params
           ) do
      json(conn, %{membership: serialize_membership(membership)})
    end
  end

  defp serialize_entry(%{organization: organization, settings: settings} = entry) do
    %{
      organization: serialize_organization(organization),
      settings: serialize_settings(settings),
      canonical_path: "/org/#{organization.slug}",
      pending_registration: Map.get(entry, :pending_registration, false)
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

  defp serialize_access_membership(%{membership: membership, user: user}) do
    membership
    |> serialize_membership()
    |> Map.put(:user, serialize_user(user))
  end

  defp serialize_membership(membership) do
    %{
      id: membership.id,
      user_id: membership.user_id,
      role: membership.role,
      status: membership.status,
      joined_at: membership.joined_at,
      inserted_at: membership.inserted_at,
      updated_at: membership.updated_at
    }
  end

  defp serialize_user(nil), do: nil

  defp serialize_user(user) do
    %{
      id: user.id,
      nickname: user.nickname,
      role: user.role,
      avatar_url: user.avatar_url
    }
  end
end
