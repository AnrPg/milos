defmodule MilosTrainingWeb.LandingController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias MilosTraining.Application.{GetLandingPage, SetLeaderboardPreference}
  alias OpenApiSpex.Schema

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Landing"])
  security([%{"bearerAuth" => []}])

  @theme_slugs ~w(ember sage steel aurora royal volt noir daybreak paper lagoon sunset)

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [:update_leaderboard_preference]

  @leaderboard_entry %Schema{
    type: :object,
    properties: %{
      rank: %Schema{type: :integer},
      user_id: %Schema{type: :string, format: :uuid},
      nickname: %Schema{type: :string},
      workouts_this_week: %Schema{type: :integer},
      prs_this_month: %Schema{type: :integer}
    },
    required: [:rank, :user_id, :nickname, :workouts_this_week, :prs_this_month]
  }

  @coach_note_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      admin_id: %Schema{type: :string, format: :uuid},
      athlete_id: %Schema{type: :string, format: :uuid},
      body: %Schema{type: :string},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :admin_id, :athlete_id, :body, :inserted_at]
  }

  @membership_schema %Schema{
    type: :object,
    nullable: true,
    properties: %{
      package_name: %Schema{type: :string, nullable: true},
      package_code: %Schema{type: :string, nullable: true},
      expiration_date: %Schema{type: :string, format: :date, nullable: true},
      last_paid: %Schema{type: :string, format: :date, nullable: true},
      amount: %Schema{type: :integer, nullable: true},
      currency: %Schema{type: :string},
      notes: %Schema{type: :string, nullable: true},
      entitlement_status: %Schema{type: :string},
      entitlement_source: %Schema{type: :string}
    },
    required: [:currency, :entitlement_status, :entitlement_source]
  }

  @gamification_settings_schema %Schema{
    type: :object,
    properties: %{
      weekly_workout_target: %Schema{type: :integer, minimum: 1},
      streak_shield_reset_day: %Schema{type: :integer, minimum: 1, maximum: 28, nullable: true},
      leaderboard_enabled: %Schema{type: :boolean},
      theme_slug: %Schema{type: :string, enum: @theme_slugs}
    },
    required: [:weekly_workout_target, :leaderboard_enabled, :theme_slug]
  }

  operation(:show,
    summary: "Fetch the authenticated landing page payload",
    responses: [
      ok:
        {"Landing payload", "application/json",
         %Schema{
           type: :object,
           properties: %{
             gamification: %Schema{
               type: :object,
               properties: %{
                 settings: @gamification_settings_schema
               },
               required: [:settings],
               additionalProperties: true
             },
             coach_notes: %Schema{type: :array, items: @coach_note_schema},
             membership: @membership_schema,
             recent_executions: %Schema{type: :array, items: %Schema{type: :object}}
           },
           required: [:gamification, :coach_notes, :membership, :recent_executions]
         }}
    ]
  )

  def show(conn, _params) do
    user = GuardianPlug.current_resource(conn)

    with {:ok, payload} <- GetLandingPage.call(user) do
      json(conn, payload)
    end
  end

  operation(:update_leaderboard_preference,
    summary: "Update leaderboard opt-in preference",
    request_body:
      {"Leaderboard opt-in", "application/json",
       %Schema{
         type: :object,
         required: [:opted_in],
         properties: %{opted_in: %Schema{type: :boolean}}
       }},
    responses: [
      ok:
        {"Leaderboard preference", "application/json",
         %Schema{
           type: :object,
           properties: %{
             opted_in: %Schema{type: :boolean},
             visible: %Schema{type: :boolean},
             weekly: %Schema{type: :array, items: @leaderboard_entry},
             monthly: %Schema{type: :array, items: @leaderboard_entry}
           },
           required: [:opted_in, :visible, :weekly, :monthly]
         }}
    ]
  )

  def update_leaderboard_preference(conn, params) do
    user = GuardianPlug.current_resource(conn)
    body = normalize_body_params(conn, params)

    with {:ok, payload} <- SetLeaderboardPreference.call(user, body) do
      json(conn, payload)
    end
  end

  defp normalize_body_params(conn, params) do
    case conn.body_params do
      %{} = body_params when map_size(body_params) > 0 -> body_params
      _ -> Map.get(params, "body") || Map.get(params, :body) || params
    end
  end
end
