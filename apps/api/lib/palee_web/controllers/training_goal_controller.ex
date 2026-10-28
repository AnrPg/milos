defmodule PaleeWeb.TrainingGoalController do
  @moduledoc """
  The weekly workout goal is the person's own (ADR-229). The person reads and
  sets theirs; a coach (their clients) or an owner/admin with full coaching
  scope (any client of the box) reads and sets it from the client's profile.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.{AuthorizeClientAccess, GetTrainingGoal, SetTrainingGoal}

  @goal_min Palee.Gamification.weekly_goal_range().first
  @goal_max Palee.Gamification.weekly_goal_range().last

  action_fallback PaleeWeb.FallbackController

  tags(["Gamification"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @user_id %Parameter{
    name: :user_id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  @goal_schema %Schema{
    title: "TrainingGoal",
    type: :object,
    properties: %{
      weekly_workout_target: %Schema{
        type: :integer,
        minimum: @goal_min,
        maximum: @goal_max
      },
      is_default: %Schema{
        type: :boolean,
        description: "No one set a goal yet; the platform default applies"
      },
      set_by_role: %Schema{type: :string, enum: ["self", "coach", "staff"], nullable: true},
      set_by_id: %Schema{type: :string, format: :uuid, nullable: true},
      set_by_nickname: %Schema{type: :string, nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true},
      min: %Schema{type: :integer},
      max: %Schema{type: :integer}
    },
    required: [:is_default, :max, :min, :weekly_workout_target]
  }

  @goal_response %Schema{
    type: :object,
    properties: %{goal: @goal_schema},
    required: [:goal]
  }

  @goal_request %Schema{
    type: :object,
    additionalProperties: false,
    properties: %{
      weekly_workout_target: %Schema{
        type: :integer,
        minimum: @goal_min,
        maximum: @goal_max
      }
    },
    required: [:weekly_workout_target]
  }

  @error %Schema{type: :object, additionalProperties: true}

  operation(:show,
    summary: "My weekly workout goal",
    responses: [ok: {"Goal", "application/json", @goal_response}]
  )

  def show(conn, _params) do
    user = GuardianPlug.current_resource(conn)

    with {:ok, goal} <- GetTrainingGoal.call(conn.assigns.user_context, user.id) do
      json(conn, %{goal: goal})
    end
  end

  operation(:update,
    summary: "Set my weekly workout goal",
    request_body: {"Goal", "application/json", @goal_request},
    responses: [
      ok: {"Goal", "application/json", @goal_response},
      unprocessable_entity: {"Error", "application/json", @error}
    ]
  )

  def update(conn, _params) do
    user = GuardianPlug.current_resource(conn)

    with {:ok, goal} <-
           SetTrainingGoal.call(conn.assigns.user_context, user, user.id, conn.body_params) do
      json(conn, %{goal: goal})
    end
  end

  operation(:client_show,
    summary: "A client's weekly workout goal",
    parameters: [@user_id],
    responses: [
      ok: {"Goal", "application/json", @goal_response},
      forbidden: {"Not allowed", "application/json", @error}
    ]
  )

  def client_show(conn, %{user_id: user_id}) do
    context = conn.assigns.tenant_context

    with :ok <- AuthorizeClientAccess.call(context, :manage_coaching, user_id),
         {:ok, goal} <- GetTrainingGoal.call(context, user_id) do
      json(conn, %{goal: goal})
    end
  end

  operation(:client_update,
    summary: "Set a client's weekly workout goal; the client is notified",
    parameters: [@user_id],
    request_body: {"Goal", "application/json", @goal_request},
    responses: [
      ok: {"Goal", "application/json", @goal_response},
      forbidden: {"Not allowed", "application/json", @error},
      unprocessable_entity: {"Error", "application/json", @error}
    ]
  )

  def client_update(conn, %{user_id: user_id}) do
    staff = GuardianPlug.current_resource(conn)
    context = conn.assigns.tenant_context

    with :ok <- AuthorizeClientAccess.call(context, :manage_coaching, user_id),
         {:ok, goal} <- SetTrainingGoal.call(context, staff, user_id, conn.body_params) do
      json(conn, %{goal: goal})
    end
  end
end
