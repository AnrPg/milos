defmodule MilosTrainingWeb.AdminUserController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    GetAdminUserCoachingContext,
    GetAdminUserFinance,
    GetAdminUserIncidents,
    GetAdminUserMessages,
    GetAdminUserProfile,
    GetAdminUserPRs,
    GetAdminUserTrainingHistory,
    GrantUserAllowance,
    ListAdminUsers,
    ListAthletes,
    RevokeUserAllowance,
    UpdateUserRole
  }

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Admin Users"])
  security([%{"bearerAuth" => []}])

  @id_parameter %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @user_id %Schema{type: :string, format: :uuid}
  @summary_object %Schema{type: :object, additionalProperties: true}
  @finance_response %Schema{
    type: :object,
    required: [:user_id, :available, :summary, :drill_down, :operational_links],
    properties: %{
      user_id: @user_id,
      available: %Schema{type: :boolean},
      summary: %Schema{type: :object, additionalProperties: true, nullable: true},
      drill_down: %Schema{type: :object, additionalProperties: true, nullable: true},
      operational_links: %Schema{type: :object, additionalProperties: %Schema{type: :string}}
    }
  }
  @training_response %Schema{
    type: :object,
    required: [:user_id, :executions, :scores, :class_participation, :assigned_workouts, :summary],
    properties: %{
      user_id: @user_id,
      executions: %Schema{type: :array, items: @summary_object},
      scores: %Schema{type: :array, items: @summary_object},
      class_participation: %Schema{type: :array, items: @summary_object},
      assigned_workouts: %Schema{type: :array, items: @summary_object},
      summary: @summary_object
    }
  }
  @collection_response %Schema{
    type: :object,
    required: [:user_id],
    properties: %{
      user_id: @user_id,
      prs: %Schema{type: :array, items: @summary_object},
      incidents: %Schema{type: :array, items: @summary_object},
      threads: %Schema{type: :array, items: @summary_object},
      summary: @summary_object,
      operational_links: %Schema{type: :object, additionalProperties: %Schema{type: :string}}
    }
  }
  @coaching_response %Schema{
    type: :object,
    required: [:user_id, :available, :drill_down],
    properties: %{
      user_id: @user_id,
      available: %Schema{type: :boolean},
      drill_down: %Schema{type: :object, additionalProperties: true, nullable: true}
    }
  }

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [:update_role, :grant_allowance, :revoke_allowance]

  @allowance_grant_body %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          additionalProperties: false,
          required: [:allowance, :quantity, :period, :reason],
          properties: %{
            allowance: %Schema{
              type: :string,
              enum: ["class_visits", "coaching_touchpoints"]
            },
            quantity: %Schema{type: :integer, minimum: 1, maximum: 10_000},
            period: %Schema{
              type: :string,
              enum: ["calendar_week", "calendar_month", "subscription_period"]
            },
            occurred_on: %Schema{type: :string, format: :date, nullable: true},
            reason: %Schema{type: :string, minLength: 3, maxLength: 500},
            idempotency_key: %Schema{type: :string, minLength: 8, maxLength: 200, nullable: true}
          }
        }
      }
    }
  }
  @allowance_revoke_body %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          additionalProperties: false,
          required: [:reason],
          properties: %{reason: %Schema{type: :string, minLength: 3, maxLength: 500}}
        }
      }
    }
  }

  operation(:index,
    summary: "List all users for the admin directory",
    parameters: [
      %Parameter{name: :q, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{
        name: :role,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["member", "athlete", "admin"]}
      },
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 50}
      },
      %Parameter{
        name: :offset,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 0}
      }
    ],
    responses: [
      ok:
        {"User directory", "application/json", %Schema{type: :object, additionalProperties: true}}
    ]
  )

  operation(:show,
    summary: "Get the common role-aware admin user profile shell",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok:
        {"User profile shell", "application/json",
         %Schema{type: :object, additionalProperties: true}},
      not_found:
        {"Not found", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}, required: [:error]}}
    ]
  )

  operation(:finance,
    summary: "Get a user's finance dossier section",
    parameters: [@id_parameter],
    responses: [ok: {"Finance profile", "application/json", @finance_response}]
  )

  operation(:training_history,
    summary: "Get a user's executions, scores, assignments, and class participation",
    parameters: [@id_parameter],
    responses: [ok: {"Training history", "application/json", @training_response}]
  )

  operation(:prs,
    summary: "Get a user's personal records",
    parameters: [@id_parameter],
    responses: [ok: {"Personal records", "application/json", @collection_response}]
  )

  operation(:incidents,
    summary: "Get a user's health and injury incidents",
    parameters: [@id_parameter],
    responses: [ok: {"Health incidents", "application/json", @collection_response}]
  )

  operation(:messages,
    summary: "Get a user's communication thread summary",
    parameters: [@id_parameter],
    responses: [ok: {"Communication summary", "application/json", @collection_response}]
  )

  operation(:coaching_context,
    summary: "Get role-aware coaching context for a user",
    parameters: [@id_parameter],
    responses: [ok: {"Coaching context", "application/json", @coaching_response}]
  )

  operation(:index_athletes,
    summary: "List athlete users",
    parameters: [
      %Parameter{
        name: :q,
        in: :query,
        required: false,
        schema: %Schema{type: :string}
      }
    ],
    responses: [
      ok:
        {"Athletes", "application/json",
         %Schema{
           type: :object,
           properties: %{
             athletes: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   id: %Schema{type: :string, format: :uuid},
                   nickname: %Schema{type: :string},
                   role: %Schema{type: :string}
                 },
                 required: [:id, :nickname, :role]
               }
             }
           },
           required: [:athletes]
         }}
    ]
  )

  operation(:update_role,
    summary: "Update a user's role",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        description: "User ID",
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: %RequestBody{
      description: "Role params",
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              role: %Schema{type: :string, enum: ["member", "athlete", "admin"]}
            },
            required: [:role]
          }
        }
      }
    },
    responses: [
      ok:
        {"Updated user", "application/json",
         %Schema{
           type: :object,
           properties: %{
             id: %Schema{type: :string, format: :uuid},
             nickname: %Schema{type: :string},
             role: %Schema{type: :string}
           },
           required: [:id, :nickname, :role]
         }},
      not_found:
        {"Not found", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }},
      unauthorized:
        {"Unauthorized", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }},
      forbidden:
        {"Forbidden", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }},
      unprocessable_entity:
        {"Validation errors", "application/json",
         %Schema{
           type: :object,
           properties: %{
             errors: %Schema{
               type: :object,
               additionalProperties: %Schema{type: :array, items: %Schema{type: :string}}
             }
           },
           required: [:errors]
         }},
      internal_server_error:
        {"Unexpected server error", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }}
    ]
  )

  operation(:grant_allowance,
    summary: "Extend one user's named package allowance for a specific period",
    parameters: [@id_parameter],
    request_body: @allowance_grant_body,
    responses: [
      created: {"Allowance extension", "application/json", @summary_object},
      not_found: {"User or Finance profile not found", "application/json", @summary_object},
      unprocessable_entity: {"Invalid allowance extension", "application/json", @summary_object}
    ]
  )

  def update_role(conn, params) do
    id = params["id"] || params[:id]

    case UpdateUserRole.call(id, conn.body_params) do
      {:ok, user} ->
        json(conn, %{id: user.id, nickname: user.nickname, role: to_string(user.role)})

      error ->
        error
    end
  end

  def grant_allowance(conn, params) do
    admin = Guardian.Plug.current_resource(conn)
    user_id = params["id"] || params[:id]

    with {:ok, result} <- GrantUserAllowance.call(user_id, admin.id, conn.body_params) do
      conn
      |> put_status(:created)
      |> json(result)
    end
  end

  operation(:revoke_allowance,
    summary: "Revoke a personal allowance extension with a compensating ledger entry",
    parameters: [
      @id_parameter,
      %Parameter{name: :entry_id, in: :path, required: true, schema: @user_id}
    ],
    request_body: @allowance_revoke_body,
    responses: [
      created: {"Allowance compensation", "application/json", @summary_object},
      not_found: {"User or allowance extension not found", "application/json", @summary_object},
      unprocessable_entity:
        {"Invalid or already revoked extension", "application/json", @summary_object}
    ]
  )

  def revoke_allowance(conn, params) do
    admin = Guardian.Plug.current_resource(conn)
    user_id = params["id"] || params[:id]
    entry_id = params["entry_id"] || params[:entry_id]

    with {:ok, result} <- RevokeUserAllowance.call(user_id, admin.id, entry_id, conn.body_params) do
      conn |> put_status(:created) |> json(result)
    end
  end

  def index(conn, params) do
    with {:ok, payload} <- ListAdminUsers.call(params) do
      json(conn, payload)
    end
  end

  def show(conn, params) do
    with {:ok, payload} <- GetAdminUserProfile.call(params["id"] || params[:id]) do
      json(conn, payload)
    end
  end

  def finance(conn, params), do: render_service(conn, GetAdminUserFinance, params)

  def training_history(conn, params),
    do: render_service(conn, GetAdminUserTrainingHistory, params)

  def prs(conn, params), do: render_service(conn, GetAdminUserPRs, params)
  def incidents(conn, params), do: render_service(conn, GetAdminUserIncidents, params)
  def messages(conn, params), do: render_service(conn, GetAdminUserMessages, params)

  def coaching_context(conn, params) do
    id = params["id"] || params[:id]

    with {:ok, payload} <- GetAdminUserCoachingContext.call(id, params) do
      json(conn, payload)
    end
  end

  def index_athletes(conn, params) do
    json(conn, %{athletes: ListAthletes.call(params["q"] || params[:q])})
  end

  defp render_service(conn, service, params) do
    with {:ok, payload} <- service.call(params["id"] || params[:id]) do
      json(conn, payload)
    end
  end
end
