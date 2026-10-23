defmodule PaleeWeb.Schemas.PlatformPlans do
  @moduledoc "OpenAPI shapes of platform plans and the solo-coach tier (ADR-170)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  @limit_keys ~w(staff_seats active_clients)

  def limits do
    %Schema{
      title: "PlatformPlanLimits",
      type: :object,
      description: "Absent key = unlimited",
      properties:
        Map.new(@limit_keys, &{String.to_atom(&1), %Schema{type: :integer, minimum: 1}}),
      additionalProperties: false
    }
  end

  def plan do
    %Schema{
      title: "PlatformPlan",
      type: :object,
      properties: %{
        code: %Schema{type: :string},
        audience: %Schema{type: :string, enum: ["gym", "coach", "organiser"]},
        name: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true},
        limits: limits(),
        monthly_price_cents: %Schema{type: :integer, nullable: true},
        annual_price_cents: %Schema{type: :integer, nullable: true},
        currency: %Schema{type: :string},
        price_status: %Schema{type: :string, enum: ["placeholder", "confirmed"]},
        trial_days: %Schema{type: :integer},
        is_default: %Schema{type: :boolean},
        public: %Schema{type: :boolean},
        active: %Schema{type: :boolean},
        position: %Schema{type: :integer}
      },
      required: [
        :code,
        :audience,
        :name,
        :description,
        :limits,
        :monthly_price_cents,
        :annual_price_cents,
        :currency,
        :price_status,
        :trial_days,
        :is_default,
        :public,
        :active,
        :position
      ]
    }
  end

  def plans do
    %Schema{
      title: "PlatformPlans",
      type: :object,
      properties: %{plans: %Schema{type: :array, items: plan()}},
      required: [:plans]
    }
  end

  def plan_body(required) do
    body(
      %{
        code: %Schema{type: :string, pattern: "^[a-z][a-z0-9_]{1,39}$"},
        audience: %Schema{type: :string, enum: ["gym", "coach"]},
        name: %Schema{type: :string, minLength: 1, maxLength: 80},
        description: %Schema{type: :string, nullable: true, maxLength: 500},
        limits: limits(),
        monthly_price_cents: %Schema{type: :integer, minimum: 0, nullable: true},
        annual_price_cents: %Schema{type: :integer, minimum: 0, nullable: true},
        currency: %Schema{type: :string, pattern: "^[A-Za-z]{3}$"},
        price_status: %Schema{type: :string, enum: ["placeholder", "confirmed"]},
        trial_days: %Schema{type: :integer, minimum: 0, maximum: 365},
        is_default: %Schema{type: :boolean},
        public: %Schema{type: :boolean},
        active: %Schema{type: :boolean},
        position: %Schema{type: :integer}
      },
      required
    )
  end

  def subscription do
    %Schema{
      title: "OrganizationPlatformSubscription",
      type: :object,
      properties: %{
        organization_id: %Schema{type: :string, format: :uuid},
        plan_code: %Schema{type: :string},
        status: %Schema{
          type: :string,
          enum: ~w(trialing active past_due cancelled comped trial_expired)
        },
        stored_status: %Schema{type: :string, enum: ~w(trialing active past_due cancelled comped)},
        trial_ends_at: %Schema{type: :string, format: :"date-time", nullable: true},
        price_override_cents: %Schema{type: :integer, nullable: true},
        notes: %Schema{type: :string, nullable: true},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [
        :organization_id,
        :plan_code,
        :status,
        :stored_status,
        :trial_ends_at,
        :price_override_cents,
        :notes,
        :updated_at
      ]
    }
  end

  def subscriptions do
    %Schema{
      title: "OrganizationPlatformSubscriptions",
      type: :object,
      properties: %{subscriptions: %Schema{type: :array, items: subscription()}},
      required: [:subscriptions]
    }
  end

  def assignment_body do
    body(
      %{
        plan_code: %Schema{type: :string},
        status: %Schema{type: :string, enum: ~w(trialing active past_due cancelled comped)},
        trial_ends_at: %Schema{type: :string, format: :"date-time", nullable: true},
        price_override_cents: %Schema{type: :integer, minimum: 0, nullable: true},
        notes: %Schema{type: :string, nullable: true, maxLength: 1000}
      },
      [:plan_code, :status]
    )
  end

  def organization_plan do
    %Schema{
      title: "OrganizationPlan",
      type: :object,
      properties: %{
        plan: %Schema{allOf: [plan()], nullable: true},
        status: %Schema{
          type: :string,
          nullable: true,
          enum: ~w(trialing active past_due cancelled comped trial_expired)
        },
        notice: %Schema{
          type: :string,
          nullable: true,
          enum: ~w(trial_ending trial_expired past_due cancelled)
        },
        trial_ends_at: %Schema{type: :string, format: :"date-time", nullable: true},
        trial_days_left: %Schema{type: :integer, nullable: true},
        price_override_cents: %Schema{type: :integer, nullable: true},
        usage: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              key: %Schema{type: :string, enum: @limit_keys},
              used: %Schema{type: :integer},
              limit: %Schema{type: :integer, nullable: true, description: "null = unlimited"},
              hard: %Schema{type: :boolean},
              state: %Schema{type: :string, enum: ~w(ok near reached over)}
            },
            required: [:key, :used, :limit, :hard, :state]
          }
        }
      },
      required: [
        :plan,
        :status,
        :notice,
        :trial_ends_at,
        :trial_days_left,
        :price_override_cents,
        :usage
      ]
    }
  end

  def coach_practice_body do
    body(
      %{
        name: %Schema{type: :string, minLength: 2, maxLength: 120},
        team_name: %Schema{type: :string, nullable: true, maxLength: 80},
        timezone: %Schema{type: :string, nullable: true},
        default_locale: %Schema{type: :string, nullable: true}
      },
      [:name]
    )
  end

  def coach_practice do
    %Schema{
      title: "CoachPractice",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        slug: %Schema{type: :string},
        name: %Schema{type: :string},
        provider_kind: %Schema{type: :string, enum: ["coach"]}
      },
      required: [:id, :slug, :name, :provider_kind]
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
