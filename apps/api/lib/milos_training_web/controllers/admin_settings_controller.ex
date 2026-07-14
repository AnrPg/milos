defmodule MilosTrainingWeb.AdminSettingsController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{GetAdminSettings, UpdateAdminSettings}
  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Admin Settings"])
  security([%{"bearerAuth" => []}])

  @theme_slugs ~w(ember sage steel aurora royal volt noir daybreak paper lagoon sunset)

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

  @finance_settings_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, nullable: true},
      payment_reminder_interval_days: %Schema{type: :integer, minimum: 1},
      inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:payment_reminder_interval_days]
  }

  @admin_settings_response_schema %Schema{
    type: :object,
    properties: %{
      gamification: @gamification_settings_schema,
      finance: @finance_settings_schema
    },
    required: [:gamification, :finance]
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
          payment_reminder_interval_days: %Schema{type: :integer, minimum: 1}
        },
        required: []
      }
    },
    required: [:gamification]
  }

  operation(:show,
    summary: "Fetch global admin settings",
    responses: [
      ok: {"Admin settings", "application/json", @admin_settings_response_schema}
    ]
  )

  def show(conn, _params) do
    with {:ok, payload} <- GetAdminSettings.call() do
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
    with {:ok, payload} <- UpdateAdminSettings.call(conn.body_params) do
      json(conn, payload)
    end
  end
end
