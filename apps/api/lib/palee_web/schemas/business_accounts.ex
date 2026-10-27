defmodule PaleeWeb.Schemas.BusinessAccounts do
  @moduledoc "OpenAPI schemas of ADR-184: business accounts, demo data and activation."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  @business_kind %Schema{type: :string, enum: ["gym", "coach"]}
  @activation %Schema{type: :string, enum: ["demo", "active"]}
  @uuid %Schema{type: :string, format: :uuid}
  @time %Schema{type: :string, format: :date_time}
  @nullable_time %Schema{type: :string, format: :date_time, nullable: true}
  @nullable_text %Schema{type: :string, nullable: true}

  def business_kind, do: @business_kind
  def activation, do: @activation

  def sign_up_body do
    body(
      %{
        business_kind: @business_kind,
        business_name: %Schema{type: :string, minLength: 2, maxLength: 120},
        city: %Schema{type: :string, nullable: true, maxLength: 80},
        phone: %Schema{type: :string, nullable: true, maxLength: 40},
        message: %Schema{type: :string, nullable: true, maxLength: 1000},
        timezone: @nullable_text,
        default_locale: @nullable_text
      },
      [:business_kind, :business_name]
    )
  end

  def conversion_body do
    body(
      %{
        business_kind: @business_kind,
        business_name: %Schema{type: :string, minLength: 2, maxLength: 120},
        city: %Schema{type: :string, nullable: true, maxLength: 80},
        phone: %Schema{type: :string, nullable: true, maxLength: 40},
        message: %Schema{type: :string, nullable: true, maxLength: 1000}
      },
      [:business_kind, :business_name]
    )
  end

  def activation_request_body do
    body(
      %{
        phone: %Schema{type: :string, nullable: true, maxLength: 40},
        city: %Schema{type: :string, nullable: true, maxLength: 80},
        message: %Schema{type: :string, nullable: true, maxLength: 1000}
      },
      []
    )
  end

  def seed_body do
    body(
      %{
        section: %Schema{
          type: :string,
          description: "A demo section (members, schedule, finance, workouts) or all"
        }
      },
      [:section]
    )
  end

  def token_body do
    body(%{token: %Schema{type: :string, minLength: 20, maxLength: 256}}, [:token])
  end

  def decision_body do
    body(
      %{
        decision: %Schema{type: :string, enum: ["approve", "decline"]},
        note: %Schema{type: :string, nullable: true, maxLength: 500},
        role: %Schema{
          type: :string,
          enum: ["owner", "admin"],
          description: "Activation requests: the role the link grants"
        }
      },
      [:decision]
    )
  end

  def issue_link_body do
    body(
      %{
        user_id: %Schema{type: :string, format: :uuid, nullable: true},
        nickname: %Schema{type: :string, nullable: true},
        role: %Schema{type: :string, enum: ["owner", "admin"]},
        lifetime_seconds: %Schema{type: :integer, minimum: 3600, maximum: 2_592_000}
      },
      [:role]
    )
  end

  def business_organization do
    %Schema{
      title: "BusinessOrganization",
      type: :object,
      properties: %{
        id: @uuid,
        slug: %Schema{type: :string},
        name: %Schema{type: :string},
        provider_kind: %Schema{type: :string},
        activation: @activation,
        demo_started_at: @nullable_time,
        activated_at: @nullable_time
      },
      required: [:id, :slug, :name, :provider_kind, :activation]
    }
  end

  def archived_demos do
    %Schema{
      title: "BusinessArchivedDemos",
      type: :object,
      properties: %{
        businesses: %Schema{
          type: :array,
          items: %Schema{
            title: "BusinessArchivedDemo",
            type: :object,
            properties: %{
              id: @uuid,
              slug: %Schema{type: :string},
              name: %Schema{type: :string},
              provider_kind: @business_kind,
              demo_archived_at: @time
            },
            required: [:id, :slug, :name, :provider_kind, :demo_archived_at]
          }
        }
      },
      required: [:businesses]
    }
  end

  def reopened_demo do
    %Schema{
      title: "BusinessReopenedDemo",
      type: :object,
      properties: %{organization: business_organization(), request: request()},
      required: [:organization, :request]
    }
  end

  def demo_status do
    %Schema{
      title: "BusinessDemoStatus",
      type: :object,
      properties: %{
        activation: @activation,
        gated: %Schema{
          type: :boolean,
          description: "Demo mode applies: going-live actions answer business_not_activated"
        },
        sections: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              section: %Schema{type: :string},
              seeded: %Schema{type: :boolean},
              rows: %Schema{type: :integer}
            },
            required: [:section, :seeded, :rows]
          }
        },
        activation_request: %Schema{allOf: [request()], nullable: true}
      },
      required: [:activation, :gated, :sections]
    }
  end

  def request do
    %Schema{
      title: "BusinessRequest",
      type: :object,
      properties: %{
        id: @uuid,
        kind: %Schema{type: :string, enum: ["conversion", "activation"]},
        business_kind: @business_kind,
        business_name: %Schema{type: :string},
        city: @nullable_text,
        phone: @nullable_text,
        message: @nullable_text,
        organization_id: %Schema{type: :string, format: :uuid, nullable: true},
        status: %Schema{
          type: :string,
          enum: ["pending", "approved", "declined", "cancelled", "completed"]
        },
        decision_note: @nullable_text,
        decided_at: @nullable_time,
        requested_by: %Schema{type: :string, nullable: true, description: "Vendors: nickname"},
        requester_email_verified: %Schema{
          type: :boolean,
          nullable: true,
          description: "Vendors (ADR-205): whether the requester verified their email"
        },
        inserted_at: @time
      },
      required: [:id, :kind, :business_kind, :business_name, :status, :inserted_at]
    }
  end

  def requests do
    %Schema{
      title: "BusinessRequests",
      type: :object,
      properties: %{requests: %Schema{type: :array, items: request()}},
      required: [:requests]
    }
  end

  def activation_link do
    %Schema{
      title: "BusinessActivationLink",
      type: :object,
      properties: %{
        id: @uuid,
        organization_id: @uuid,
        user_id: @uuid,
        nickname: @nullable_text,
        role: %Schema{type: :string, enum: ["owner", "admin"]},
        state: %Schema{type: :string, enum: ["live", "expired", "redeemed", "revoked"]},
        expires_at: @time,
        inserted_at: @time,
        token: %Schema{type: :string, nullable: true, description: "Only when just issued"},
        path: %Schema{type: :string, nullable: true, description: "Only when just issued"},
        email_delivery: %Schema{
          title: "BusinessActivationLinkEmail",
          type: :object,
          nullable: true,
          description:
            "ADR-205: the link's email to the account. `not_sent` when the outbox refused it " <>
              "(`error` says why); the link still works and can be copied.",
          properties: %{
            status: %Schema{
              type: :string,
              enum: ["queued", "deferred", "sent", "failed", "suppressed", "not_sent"]
            },
            error: @nullable_text,
            sent_at: @nullable_time
          },
          required: [:status]
        }
      },
      required: [:id, :organization_id, :user_id, :role, :state, :expires_at, :inserted_at]
    }
  end

  def queue do
    %Schema{
      title: "BusinessAccountsQueue",
      type: :object,
      properties: %{
        requests: %Schema{type: :array, items: request()},
        demo_businesses: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              organization: business_organization(),
              owners: %Schema{
                type: :array,
                items: %Schema{
                  type: :object,
                  properties: %{
                    user_id: @uuid,
                    nickname: @nullable_text,
                    email_verified: %Schema{
                      type: :boolean,
                      description: "ADR-205: a link is only issued to a verified email"
                    }
                  },
                  required: [:user_id, :email_verified]
                }
              },
              link: %Schema{allOf: [activation_link()], nullable: true}
            },
            required: [:organization, :owners]
          }
        }
      },
      required: [:requests, :demo_businesses]
    }
  end

  def decision_result do
    %Schema{
      title: "BusinessRequestDecision",
      type: :object,
      properties: %{
        request: request(),
        organization: %Schema{allOf: [business_organization()], nullable: true},
        activation_link: %Schema{allOf: [activation_link()], nullable: true}
      },
      required: [:request]
    }
  end

  def activation_preview do
    %Schema{
      title: "BusinessActivationPreview",
      type: :object,
      properties: %{
        organization: business_organization(),
        role: %Schema{type: :string, enum: ["owner", "admin"]},
        expires_at: @time,
        demo: %Schema{
          type: :object,
          properties: %{
            rows: %Schema{type: :integer},
            people: %Schema{type: :integer},
            sections: %Schema{type: :array, items: %Schema{type: :string}}
          },
          required: [:rows, :people, :sections]
        }
      },
      required: [:organization, :role, :expires_at, :demo]
    }
  end

  def activation_result do
    %Schema{
      title: "BusinessActivationResult",
      type: :object,
      properties: %{
        organization: business_organization(),
        roles: %Schema{type: :array, items: %Schema{type: :string}},
        removed: %Schema{
          type: :object,
          properties: %{rows: %Schema{type: :integer}, people: %Schema{type: :integer}},
          required: [:rows, :people]
        }
      },
      required: [:organization, :roles, :removed]
    }
  end

  defp body(properties, required) do
    %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{type: :object, properties: properties, required: required}
        }
      }
    }
  end
end
