defmodule MilosTrainingWeb.AuthController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{LoginUser, RefreshToken, RegisterUser}
  alias MilosTraining.Identity.Queries.FindUser
  alias Guardian.Plug, as: GuardianPlug
  alias OpenApiSpex.{RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Authentication"])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [:register, :login, :refresh, :nickname_available]

  operation(:register,
    summary: "Register a new user",
    request_body: %RequestBody{
      description: "Registration params",
      required: true,
      content: %{
        "application/json" => %OpenApiSpex.MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              nickname: %Schema{type: :string},
              password: %Schema{type: :string},
              role: %Schema{type: :string, enum: ["member", "athlete"]}
            },
            required: [:nickname, :password, :role]
          }
        }
      }
    },
    responses: [
      created:
        {"Auth tokens", "application/json",
         %Schema{
           type: :object,
           properties: %{
             access_token: %Schema{type: :string},
             refresh_token: %Schema{type: :string}
           },
           required: [:access_token, :refresh_token]
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
      too_many_requests:
        {"Rate limited", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }},
      internal_server_error:
        {"Auth service unavailable", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }},
      service_unavailable:
        {"Dependency unavailable", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }}
    ]
  )

  operation(:login,
    summary: "Log in a user",
    request_body: %RequestBody{
      description: "Login params",
      required: true,
      content: %{
        "application/json" => %OpenApiSpex.MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              nickname: %Schema{type: :string},
              password: %Schema{type: :string}
            },
            required: [:nickname, :password]
          }
        }
      }
    },
    responses: [
      ok:
        {"Auth tokens", "application/json",
         %Schema{
           type: :object,
           properties: %{
             access_token: %Schema{type: :string},
             refresh_token: %Schema{type: :string}
           },
           required: [:access_token, :refresh_token]
         }},
      unauthorized:
        {"Unauthorized", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }},
      too_many_requests:
        {"Rate limited", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }},
      internal_server_error:
        {"Auth service unavailable", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }},
      service_unavailable:
        {"Dependency unavailable", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }}
    ]
  )

  operation(:refresh,
    summary: "Refresh an access token",
    request_body: %RequestBody{
      description: "Refresh params",
      required: true,
      content: %{
        "application/json" => %OpenApiSpex.MediaType{
          schema: %Schema{
            type: :object,
            properties: %{refresh_token: %Schema{type: :string}},
            required: [:refresh_token]
          }
        }
      }
    },
    responses: [
      ok:
        {"Auth tokens", "application/json",
         %Schema{
           type: :object,
           properties: %{
             access_token: %Schema{type: :string},
             refresh_token: %Schema{type: :string}
           },
           required: [:access_token, :refresh_token]
         }},
      unauthorized:
        {"Unauthorized", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }},
      too_many_requests:
        {"Rate limited", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }},
      internal_server_error:
        {"Auth service unavailable", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }},
      service_unavailable:
        {"Dependency unavailable", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }}
    ]
  )

  operation(:nickname_available,
    summary: "Check whether a nickname is available for registration",
    parameters: [
      %OpenApiSpex.Parameter{
        name: :nickname,
        in: :query,
        required: true,
        schema: %Schema{type: :string}
      }
    ],
    responses: [
      ok:
        {"Availability result", "application/json",
         %Schema{
           type: :object,
           properties: %{available: %Schema{type: :boolean}},
           required: [:available]
         }}
    ]
  )

  operation(:me,
    summary: "Return the authenticated user",
    security: [%{"bearerAuth" => []}],
    responses: [
      ok:
        {"Current user", "application/json",
         %Schema{
           type: :object,
           properties: %{
             id: %Schema{type: :string, format: :uuid},
             nickname: %Schema{type: :string},
             role: %Schema{type: :string},
             avatar_url: %Schema{type: :string, nullable: true},
             preferred_locale: %Schema{
               type: :string,
               enum: MilosTraining.Identity.supported_locales()
             }
           },
           required: [:id, :nickname, :role, :preferred_locale]
         }},
      unauthorized:
        {"Unauthorized", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }}
    ]
  )

  def nickname_available(conn, %{nickname: nickname}) do
    available = is_nil(FindUser.by_nickname(nickname))
    json(conn, %{available: available})
  end

  def register(conn, _params) do
    case RegisterUser.call(conn.body_params) do
      {:ok, %{access_token: access_token, refresh_token: refresh_token}} ->
        conn
        |> put_status(:created)
        |> json(%{access_token: access_token, refresh_token: refresh_token})

      error ->
        error
    end
  end

  def login(conn, _params) do
    case LoginUser.call(conn.body_params) do
      {:ok, %{access_token: access_token, refresh_token: refresh_token}} ->
        json(conn, %{access_token: access_token, refresh_token: refresh_token})

      error ->
        error
    end
  end

  def refresh(conn, _params) do
    case RefreshToken.call(conn.body_params) do
      {:ok, %{access_token: access_token, refresh_token: refresh_token}} ->
        json(conn, %{access_token: access_token, refresh_token: refresh_token})

      error ->
        error
    end
  end

  def me(conn, _params) do
    user = GuardianPlug.current_resource(conn)

    json(conn, %{
      id: user.id,
      nickname: user.nickname,
      role: to_string(user.role),
      avatar_url: user.avatar_url,
      preferred_locale: user.preferred_locale
    })
  end
end
