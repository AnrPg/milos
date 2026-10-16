defmodule MilosTrainingWeb.AdminSettingsController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{GetAdminSettings, UpdateAdminSettings}
  alias MilosTraining.Finance
  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Admin Settings"])
  security([%{"bearerAuth" => []}])

  @theme_slugs MilosTraining.Themes.slugs()

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:update]

  @gamification_settings_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, nullable: true},
      weekly_workout_target: %Schema{type: :integer, minimum: 1},
      streak_shield_reset_day: %Schema{type: :integer, minimum: 1, maximum: 28, nullable: true},
      leaderboard_enabled: %Schema{type: :boolean},
      theme_slug: %Schema{type: :string, enum: @theme_slugs},
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:weekly_workout_target, :leaderboard_enabled, :theme_slug]
  }

  @expiry_reminder_days_schema %Schema{
    type: :integer,
    minimum: 0,
    maximum: 60,
    description: "Days before a subscription ends to remind the member (0 = no reminder)"
  }

  @grace_days_schema %Schema{
    type: :integer,
    minimum: 0,
    maximum: 60,
    description:
      "Slack days after a subscription ends or an invoice falls overdue before the member loses access"
  }

  @finance_settings_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, nullable: true},
      payment_reminder_interval_days: %Schema{type: :integer, minimum: 1},
      subscription_expiry_reminder_days: @expiry_reminder_days_schema,
      subscription_grace_days: @grace_days_schema,
      document_mode: %Schema{type: :string, enum: ["invoice", "receipt"]},
      package_modules: %Schema{type: :array, items: %Schema{type: :string}},
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [
      :payment_reminder_interval_days,
      :subscription_expiry_reminder_days,
      :subscription_grace_days,
      :document_mode
    ]
  }

  @notification_push_settings_schema %Schema{
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

  @scheduling_settings_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, nullable: true},
      default_capacity: %Schema{type: :integer, minimum: 1, maximum: 500},
      default_auto_approve: %Schema{type: :boolean},
      default_booking_timeout_minutes: %Schema{type: :integer, minimum: 1, maximum: 10_080},
      default_booking_window_days: %Schema{
        type: :integer,
        minimum: 1,
        maximum: 365,
        nullable: true
      },
      default_cancellation_cutoff_hours: %Schema{
        type: :integer,
        minimum: 0,
        maximum: 168,
        nullable: true
      },
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:default_capacity, :default_auto_approve, :default_booking_timeout_minutes]
  }

  @admin_settings_response_schema %Schema{
    type: :object,
    properties: %{
      gamification: @gamification_settings_schema,
      finance: @finance_settings_schema,
      notifications: @notification_push_settings_schema,
      scheduling: @scheduling_settings_schema
    },
    required: [:gamification, :finance, :notifications, :scheduling]
  }

  @admin_settings_update_schema %Schema{
    type: :object,
    properties: %{
      gamification: %Schema{
        type: :object,
        properties: %{
          weekly_workout_target: %Schema{type: :integer, minimum: 1},
          streak_shield_reset_day: %Schema{
            type: :integer,
            minimum: 1,
            maximum: 28,
            nullable: true
          },
          leaderboard_enabled: %Schema{type: :boolean},
          theme_slug: %Schema{type: :string, enum: @theme_slugs}
        },
        required: []
      },
      finance: %Schema{
        type: :object,
        properties: %{
          payment_reminder_interval_days: %Schema{type: :integer, minimum: 1},
          subscription_expiry_reminder_days: @expiry_reminder_days_schema,
          subscription_grace_days: @grace_days_schema,
          document_mode: %Schema{type: :string, enum: ["invoice", "receipt"]},
          package_modules: %Schema{
            type: :array,
            uniqueItems: true,
            items: %Schema{type: :string, enum: Finance.package_module_keys()}
          }
        },
        required: []
      },
      notifications: %Schema{
        type: :object,
        properties: %{
          vapid_public_key: %Schema{type: :string, nullable: true},
          vapid_private_key: %Schema{type: :string, nullable: true},
          vapid_subject: %Schema{type: :string, nullable: true}
        },
        required: []
      },
      scheduling: %Schema{
        type: :object,
        properties: %{
          default_capacity: %Schema{type: :integer, minimum: 1, maximum: 500},
          default_auto_approve: %Schema{type: :boolean},
          default_booking_timeout_minutes: %Schema{
            type: :integer,
            minimum: 1,
            maximum: 10_080
          },
          default_booking_window_days: %Schema{
            type: :integer,
            minimum: 1,
            maximum: 365,
            nullable: true,
            description: "How many days ahead members may book when their package sets no window"
          },
          default_cancellation_cutoff_hours: %Schema{
            type: :integer,
            minimum: 0,
            maximum: 168,
            nullable: true,
            description: "Withdrawals closer to the class than this use the visit"
          }
        },
        required: []
      }
    },
    required: []
  }

  operation(:show,
    summary: "Fetch global admin settings",
    responses: [
      ok: {"Admin settings", "application/json", @admin_settings_response_schema}
    ]
  )

  def show(conn, _params) do
    with {:ok, payload} <- GetAdminSettings.call(conn.assigns.tenant_context) do
      json(conn, payload)
    end
  end

  operation(:update,
    summary: "Update global admin settings",
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: @admin_settings_update_schema}}
    },
    responses: [
      ok: {"Admin settings", "application/json", @admin_settings_response_schema}
    ]
  )

  def update(conn, _params) do
    with {:ok, payload} <-
           UpdateAdminSettings.call(conn.assigns.tenant_context, conn.body_params) do
      json(conn, payload)
    end
  end
end
