defmodule PaleeWeb.OrganizationAccessController do
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug

  alias Palee.Application.{
    InspectOrganizationJoinLink,
    InspectRegistrationInvitation,
    InvitationEmails,
    IssueRegistrationInvitation,
    JoinOrganizationByLink,
    ListOrganizationInvitations,
    ListOrganizationMemberships,
    ManageOrganizationJoinLink,
    RedeemRegistrationInvitation,
    RevokeRegistrationInvitation
  }

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController
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
      slug: %Schema{type: :string},
      # ADR-170: a gym or an independent coach's practice; ADR-185: a person's own events (organiser).
      provider_kind: %Schema{type: :string, enum: ["gym", "coach", "organiser"]},
      timezone: %Schema{
        type: :string,
        description:
          "ADR-179 (memberships only): the gym's IANA zone; its classes and events show on this clock"
      },
      timezone_confirmed: %Schema{
        type: :boolean,
        description:
          "ADR-179 (memberships only): an admin confirmed the zone (else it is a guess or the default)"
      },
      activation: %Schema{
        type: :string,
        enum: ["demo", "active"],
        description:
          "ADR-184 (memberships only): a business in demo mode works on demo data until the platform team activates it"
      }
    },
    required: [:id, :name, :slug]
  }

  @organization_settings_schema %Schema{
    type: :object,
    nullable: true,
    properties: %{
      brand_name: %Schema{type: :string, nullable: true},
      brand_logo_url: %Schema{type: :string, nullable: true},
      brand_primary_color: %Schema{type: :string, nullable: true},
      default_locale: %Schema{
        type: :string,
        nullable: true,
        description: "ADR-209: the box's language (its emails default to it)"
      }
    }
  }

  @delivery_status_schema %Schema{
    type: :string,
    nullable: true,
    enum: ["queued", "sent", "failed", "bounced", "suppressed"],
    description: "ADR-209: delivery of the invitation email (null when it was not emailed)"
  }

  @invitation_schema %Schema{
    type: :object,
    properties: %{
      organization: @organization_schema,
      role: %Schema{type: :string},
      roles: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "ADR-186: the role set; `role` is its primary role"
      },
      location_scope: PaleeWeb.Schemas.LocationScope.schema(),
      expires_at: %Schema{type: :string, format: :date_time},
      token: %Schema{
        type: :string,
        nullable: true,
        description: "The link token; never returned for an invitation sent by email (ADR-209)"
      },
      id: %Schema{type: :string, format: :uuid, description: "ADR-209: issue responses only"},
      email_bound: %Schema{
        type: :boolean,
        description: "ADR-209 (inspect): the invitation is for one email address, never shown"
      },
      email: %Schema{
        type: :string,
        nullable: true,
        description: "ADR-209: the address an invitation sent by email went to"
      },
      delivery_status: @delivery_status_schema
    },
    required: [:organization, :role, :expires_at]
  }

  @membership_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      role: %Schema{type: :string},
      roles: %Schema{type: :array, items: %Schema{type: :string}},
      coach_scope: %Schema{type: :string, enum: ["own", "all"]},
      notes_visible_to_admins: %Schema{type: :boolean, description: "ADR-101"},
      home_location_id: %Schema{
        type: :string,
        format: :uuid,
        nullable: true,
        description: "The location this gym opens on for the person (Phase 2)"
      },
      capabilities: %Schema{
        type: :object,
        description: "capability => scope (all, own, status), ADR-099",
        additionalProperties: %Schema{type: :string}
      },
      location_scope: PaleeWeb.Schemas.LocationScope.schema(),
      organization: @organization_schema,
      settings: @organization_settings_schema
    },
    required: [:id, :role, :roles, :capabilities, :organization]
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
              role: %Schema{
                type: :string,
                enum: ~w(owner admin coach front_desk accountant janitor member athlete),
                description: "One role (older clients); `roles` wins when both are sent"
              },
              roles: %Schema{
                type: :array,
                minItems: 1,
                items: %Schema{
                  type: :string,
                  enum: ~w(owner admin coach front_desk accountant janitor member athlete)
                },
                description: "ADR-186: the role set the invited person gets"
              },
              all_locations: %Schema{
                type: :boolean,
                description: "ADR-186: staff work at every branch («Όλα τα καταστήματα»)"
              },
              location_ids: %Schema{
                type: :array,
                maxItems: 200,
                items: %Schema{type: :string, format: :uuid},
                description:
                  "ADR-186: the branches staff work at; defaults to the issuer's own scope"
              },
              lifetime_seconds: %Schema{type: :integer, minimum: 300, maximum: 604_800},
              intended_email: %Schema{type: :string},
              send_email: %Schema{
                type: :boolean,
                description:
                  "ADR-209: email the invitation to `intended_email`; the token is then not returned"
              },
              email_locale: %Schema{
                type: :string,
                description: "ADR-209: the email's language; defaults to the box's language"
              }
            }
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

  @pending_invitation_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      role: %Schema{type: :string},
      roles: %Schema{type: :array, items: %Schema{type: :string}},
      location_scope: PaleeWeb.Schemas.LocationScope.schema(),
      expires_at: %Schema{type: :string, format: :date_time},
      issued_at: %Schema{type: :string, format: :date_time},
      email_bound: %Schema{type: :boolean},
      email: %Schema{
        type: :string,
        nullable: true,
        description: "ADR-209: the address an invitation sent by email went to"
      },
      email_locale: %Schema{type: :string, nullable: true},
      delivery_status: @delivery_status_schema
    },
    required: [:id, :role, :expires_at, :issued_at, :email_bound]
  }

  @bulk_result_schema %Schema{
    type: :object,
    properties: %{
      results: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          properties: %{
            email: %Schema{type: :string},
            status: %Schema{type: :string, enum: ["queued"]},
            invitation_id: %Schema{type: :string, format: :uuid},
            error: %Schema{type: :string, description: "Why this address got no invitation"}
          },
          required: [:email]
        }
      },
      sent: %Schema{type: :integer},
      failed: %Schema{type: :integer},
      skipped: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "Pasted values that are not email addresses"
      }
    },
    required: [:results, :sent, :failed, :skipped]
  }

  @join_link_schema %Schema{
    type: :object,
    properties: %{
      enabled: %Schema{type: :boolean},
      role: %Schema{type: :string, enum: ~w(member athlete)}
    },
    required: [:enabled, :role]
  }

  @public_join_link_schema %Schema{
    type: :object,
    properties: %{
      organization: @organization_schema,
      role: %Schema{type: :string, enum: ~w(member athlete)},
      settings: @organization_settings_schema
    },
    required: [:organization, :role]
  }

  @public_slug_parameter %Parameter{
    name: :slug,
    in: :path,
    required: true,
    schema: %Schema{type: :string}
  }

  operation(:list_invitations,
    summary: "List pending invitations of the organization",
    security: [%{"bearerAuth" => []}],
    parameters: [@organization_slug_parameter],
    responses: [
      ok:
        {"Pending invitations", "application/json",
         %Schema{type: :array, items: @pending_invitation_schema}}
    ]
  )

  operation(:bulk_invite,
    summary: "ADR-209: email one invitation to each of up to 200 addresses",
    security: [%{"bearerAuth" => []}],
    parameters: [@organization_slug_parameter],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              emails: %Schema{
                oneOf: [
                  %Schema{type: :array, maxItems: 1000, items: %Schema{type: :string}},
                  %Schema{type: :string, maxLength: 100_000}
                ],
                description: "Addresses, or pasted text / CSV holding them"
              },
              role: %Schema{type: :string},
              roles: %Schema{type: :array, items: %Schema{type: :string}},
              all_locations: %Schema{type: :boolean},
              location_ids: %Schema{type: :array, maxItems: 200, items: %Schema{type: :string}},
              lifetime_seconds: %Schema{type: :integer, minimum: 300, maximum: 604_800},
              email_locale: %Schema{type: :string}
            },
            required: [:emails]
          }
        }
      }
    },
    responses: [created: {"Per-address results", "application/json", @bulk_result_schema}]
  )

  operation(:resend,
    summary: "ADR-209: re-issue an emailed invitation and email the new link",
    security: [%{"bearerAuth" => []}],
    parameters: [@organization_slug_parameter, @invitation_id_parameter],
    responses: [created: {"The new invitation", "application/json", @pending_invitation_schema}]
  )

  operation(:show_join_link,
    summary: "Get the organization's public join link settings",
    security: [%{"bearerAuth" => []}],
    parameters: [@organization_slug_parameter],
    responses: [ok: {"Join link", "application/json", @join_link_schema}]
  )

  operation(:update_join_link,
    summary: "Enable, disable or change the role of the public join link",
    security: [%{"bearerAuth" => []}],
    parameters: [@organization_slug_parameter],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              enabled: %Schema{type: :boolean},
              role: %Schema{type: :string, enum: ~w(member athlete)}
            }
          }
        }
      }
    },
    responses: [ok: {"Join link", "application/json", @join_link_schema}]
  )

  operation(:inspect_join_link,
    summary: "Public: describe the organization behind a join link",
    parameters: [@public_slug_parameter],
    responses: [ok: {"Join link", "application/json", @public_join_link_schema}]
  )

  operation(:join,
    summary: "Join an organization through its public join link",
    security: [%{"bearerAuth" => []}],
    parameters: [@public_slug_parameter],
    responses: [
      ok: {"Already a member", "application/json", @membership_schema},
      created: {"Membership", "application/json", @membership_schema}
    ]
  )

  def list_invitations(conn, _params) do
    with {:ok, invitations} <- ListOrganizationInvitations.call(conn.assigns.tenant_context) do
      json(
        conn,
        invitations
        |> InvitationEmails.with_delivery()
        |> Enum.map(&serialize_pending_invitation/1)
      )
    end
  end

  def bulk_invite(conn, _params) do
    with {:ok, result} <- InvitationEmails.bulk(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(result)
    end
  end

  def resend(conn, %{"id" => invitation_id}) do
    with {:ok, %{invitation: invitation, message: message, address: address}} <-
           InvitationEmails.resend(conn.assigns.tenant_context, invitation_id) do
      conn
      |> put_status(:created)
      |> json(
        serialize_pending_invitation(
          Map.merge(invitation, %{email: address, delivery_status: delivery(message)})
        )
      )
    end
  end

  defp delivery(message), do: InvitationEmails.delivery_status(message)

  def show_join_link(conn, _params) do
    with {:ok, join_link} <- ManageOrganizationJoinLink.get(conn.assigns.tenant_context) do
      json(conn, join_link)
    end
  end

  def update_join_link(conn, _params) do
    with {:ok, join_link} <-
           ManageOrganizationJoinLink.update(conn.assigns.tenant_context, conn.body_params) do
      json(conn, join_link)
    end
  end

  def inspect_join_link(conn, %{"slug" => slug}) do
    with {:ok, link} <- InspectOrganizationJoinLink.call(slug) do
      json(conn, %{
        organization: %{
          id: link.organization.id,
          name: link.organization.name,
          slug: link.organization.slug
        },
        role: link.role,
        settings: serialize_settings(link.settings)
      })
    end
  end

  def join(conn, %{"slug" => slug}) do
    user = GuardianPlug.current_resource(conn)

    with {:ok, result} <- JoinOrganizationByLink.call(user, slug) do
      conn
      |> put_status(if(result.created, do: :created, else: :ok))
      |> json(serialize_membership(result))
    end
  end

  defp serialize_pending_invitation(invitation) do
    %{
      id: invitation.id,
      role: to_string(invitation.role),
      roles: invitation_roles(invitation),
      location_scope: invitation_scope(invitation),
      expires_at: invitation.expires_at,
      issued_at: invitation.inserted_at,
      email_bound: not is_nil(invitation.intended_email_digest),
      email: Map.get(invitation, :email),
      email_locale: invitation.email_locale,
      delivery_status: Map.get(invitation, :delivery_status)
    }
  end

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

  # ADR-209: `send_email` mails the invitation; its token stays in the email.
  def issue(conn, %{"send_email" => send_email}) when send_email in [true, "true"] do
    context = conn.assigns.tenant_context

    with {:ok, %{invitation: invitation, message: message, address: address}} <-
           InvitationEmails.send(context, conn.body_params) do
      conn
      |> put_status(:created)
      |> json(
        serialize_invitation(%{
          organization: context.organization,
          role: invitation.role,
          roles: invitation_roles(invitation),
          location_scope: invitation_scope(invitation),
          expires_at: invitation.expires_at
        })
        |> Map.merge(%{
          id: invitation.id,
          email: address,
          delivery_status: delivery(message)
        })
      )
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
          roles: invitation_roles(result.invitation),
          location_scope: invitation_scope(result.invitation),
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
      roles: Map.get(invitation, :roles) || [to_string(invitation.role)],
      location_scope:
        Map.get(invitation, :location_scope) || %{all_locations: true, location_ids: []},
      expires_at: invitation.expires_at,
      token: Map.get(invitation, :token)
    }
    |> then(fn value -> if value.token, do: value, else: Map.delete(value, :token) end)
    |> then(fn value ->
      case Map.fetch(invitation, :email_bound) do
        {:ok, bound} -> Map.put(value, :email_bound, bound)
        :error -> value
      end
    end)
  end

  # ADR-186: older invitations carry one role and work everywhere.
  defp invitation_roles(invitation) do
    case Map.get(invitation, :roles) do
      [_ | _] = roles -> Enum.map(roles, &to_string/1)
      _single -> [to_string(invitation.role)]
    end
  end

  defp invitation_scope(%{all_locations: false, location_ids: [_ | _] = ids}),
    do: %{all_locations: false, location_ids: ids}

  defp invitation_scope(_invitation), do: %{all_locations: true, location_ids: []}

  defp serialize_membership(%{membership: membership, organization: organization} = entry) do
    %{
      id: membership.id,
      role: to_string(membership.role),
      roles: Enum.map(membership.roles, &to_string/1),
      coach_scope: to_string(membership.coach_scope),
      notes_visible_to_admins: membership.notes_visible_to_admins != false,
      home_location_id: membership.home_location_id,
      capabilities:
        membership.roles
        |> Palee.Organizations.capabilities_for(
          membership.coach_scope,
          role_grants(Map.get(entry, :settings)),
          Map.get(entry, :location_scope, :all)
        )
        |> Map.new(fn {capability, scope} -> {to_string(capability), to_string(scope)} end),
      location_scope:
        entry |> Map.get(:location_scope, :all) |> Palee.Organizations.location_scope_payload(),
      organization: %{
        id: organization.id,
        name: organization.name,
        slug: organization.slug,
        provider_kind: Map.get(organization, :provider_kind) || "gym",
        timezone: Palee.Organizations.resolve_timezone(Map.get(entry, :settings)),
        timezone_confirmed: Palee.Organizations.timezone_confirmed?(Map.get(entry, :settings)),
        activation: Map.get(organization, :activation) || "active"
      },
      settings: serialize_settings(Map.get(entry, :settings))
    }
  end

  defp role_grants(%{settings: %{"role_grants" => grants}}) when is_map(grants), do: grants
  defp role_grants(_settings), do: %{}

  defp serialize_settings(nil), do: nil

  defp serialize_settings(settings) do
    %{
      brand_name: settings.brand_name,
      brand_logo_url: settings.brand_logo_url,
      brand_primary_color: settings.brand_primary_color,
      default_locale: Map.get(settings, :default_locale)
    }
  end
end
