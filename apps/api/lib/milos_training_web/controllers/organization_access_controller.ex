defmodule MilosTrainingWeb.OrganizationAccessController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug

  alias MilosTraining.Application.{
    InspectRegistrationInvitation,
    IssueRegistrationInvitation,
    ListOrganizationMemberships,
    RedeemRegistrationInvitation,
    RevokeRegistrationInvitation
  }

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController
  tags(["Organizations"])

  @token_request %RequestBody{
    description: "Opaque invitation token",
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          properties: %{invitation_token: %Schema{type: :string, minLength: 20, maxLength: 256}},
          required: [:invitation_token]
        }
      }
    }
  }

  @organization_slug_parameter %Parameter{
    name: :organization_slug,
    in: :path,
    required: true,
    schema: %Schema{type: :string}
  }

  @invitation_id_parameter %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  @organization_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      name: %Schema{type: :string},
      slug: %Schema{type: :string}
    },
    required: [:id, :name, :slug]
  }

  @organization_settings_schema %Schema{
    type: :object,
    nullable: true,
    properties: %{
      brand_name: %Schema{type: :string, nullable: true},
      brand_logo_url: %Schema{type: :string, nullable: true},
      brand_primary_color: %Schema{type: :string, nullable: true}
    }
  }

  @invitation_schema %Schema{
    type: :object,
    properties: %{
      organization: @organization_schema,
      role: %Schema{type: :string},
      expires_at: %Schema{type: :string, format: :date_time},
      token: %Schema{type: :string, nullable: true}
    },
    required: [:organization, :role, :expires_at]
  }

  @membership_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      role: %Schema{type: :string},
      organization: @organization_schema,
      settings: @organization_settings_schema
    },
    required: [:id, :role, :organization]
  }

  # Keep CastAndValidate on the body-only unauthenticated invitation endpoints.
  # The tenant-scoped issue/revoke routes publish required path parameters in
  # OpenAPI, while Phoenix routing and ResolveTenantContext validate the actual
  # organization slug at runtime. Running CastAndValidate on :issue makes
  # OpenApiSpex 3.22 validate scoped route params before they are represented in
  # the shape it expects, causing valid tenant requests to fail with 422.
  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:inspect, :redeem]

  operation(:inspect,
    summary: "Inspect a one-time organization invitation",
    request_body: @token_request,
    responses: [ok: {"Invitation", "application/json", @invitation_schema}]
  )

  operation(:redeem,
    summary: "Redeem an invitation for the authenticated account",
    security: [%{"bearerAuth" => []}],
    request_body: @token_request,
    responses: [created: {"Membership", "application/json", @membership_schema}]
  )

  operation(:memberships,
    summary: "List active organization memberships for the authenticated account",
    security: [%{"bearerAuth" => []}],
    responses: [
      ok: {"Memberships", "application/json", %Schema{type: :array, items: @membership_schema}}
    ]
  )

  operation(:issue,
    summary: "Issue a one-time organization invitation",
    security: [%{"bearerAuth" => []}],
    parameters: [@organization_slug_parameter],
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
    responses: [created: {"Invitation token", "application/json", @invitation_schema}]
  )

  operation(:revoke,
    summary: "Revoke an active organization invitation",
    security: [%{"bearerAuth" => []}],
    parameters: [@organization_slug_parameter, @invitation_id_parameter],
    responses: [no_content: {"Revoked", nil, nil}]
  )

  def inspect(conn, _params) do
    with {:ok, invitation} <-
           InspectRegistrationInvitation.call(conn.body_params.invitation_token) do
      json(conn, serialize_invitation(invitation))
    end
  end

  def redeem(conn, _params) do
    user = GuardianPlug.current_resource(conn)

    with {:ok, redemption} <-
           RedeemRegistrationInvitation.call(user, conn.body_params.invitation_token) do
      conn |> put_status(:created) |> json(serialize_membership(redemption))
    end
  end

  def memberships(conn, _params) do
    with {:ok, memberships} <-
           ListOrganizationMemberships.call(GuardianPlug.current_resource(conn)) do
      json(conn, Enum.map(memberships, &serialize_membership/1))
    end
  end

  def issue(conn, _params) do
    with {:ok, result} <-
           IssueRegistrationInvitation.call(conn.assigns.tenant_context, conn.body_params) do
      conn
      |> put_status(:created)
      |> json(
        serialize_invitation(%{
          organization: conn.assigns.tenant_context.organization,
          role: result.invitation.role,
          expires_at: result.invitation.expires_at,
          token: result.token
        })
      )
    end
  end

  def revoke(conn, %{"id" => invitation_id}) do
    with {:ok, _invitation} <-
           RevokeRegistrationInvitation.call(conn.assigns.tenant_context, invitation_id) do
      send_resp(conn, :no_content, "")
    end
  end

  defp serialize_invitation(invitation) do
    %{
      organization: %{
        id: invitation.organization.id,
        name: invitation.organization.name,
        slug: invitation.organization.slug
      },
      role: to_string(invitation.role),
      expires_at: invitation.expires_at,
      token: Map.get(invitation, :token)
    }
    |> then(fn value -> if value.token, do: value, else: Map.delete(value, :token) end)
  end

  defp serialize_membership(%{membership: membership, organization: organization} = entry) do
    %{
      id: membership.id,
      role: to_string(membership.role),
      organization: %{id: organization.id, name: organization.name, slug: organization.slug},
      settings: serialize_settings(Map.get(entry, :settings))
    }
  end

  defp serialize_settings(nil), do: nil

  defp serialize_settings(settings) do
    %{
      brand_name: settings.brand_name,
      brand_logo_url: settings.brand_logo_url,
      brand_primary_color: settings.brand_primary_color
    }
  end
end
