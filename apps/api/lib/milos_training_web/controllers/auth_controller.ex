defmodule MilosTrainingWeb.AuthController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    LoginUser,
    LogoutSession,
    NicknameAvailability,
    RefreshToken,
    RegisterUser,
    SignOutAllDevices
  }

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
        {"Access session", "application/json",
         %Schema{
           type: :object,
           properties: %{access_token: %Schema{type: :string}},
           required: [:access_token]
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
        {"Access session", "application/json",
         %Schema{
           type: :object,
           properties: %{access_token: %Schema{type: :string}},
           required: [:access_token]
         }},
      no_content: {"No refresh session", nil, nil},
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
    responses: [
      ok:
        {"Access session", "application/json",
         %Schema{
           type: :object,
           properties: %{access_token: %Schema{type: :string}},
           required: [:access_token]
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

  operation(:logout,
    summary: "Sign out the current browser session",
    responses: [no_content: {"Signed out", nil, nil}]
  )

  operation(:sign_out_all,
    summary: "Invalidate every session for the authenticated user",
    security: [%{"bearerAuth" => []}],
    responses: [no_content: {"All sessions invalidated", nil, nil}]
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
    with {:ok, available} <- NicknameAvailability.call(nickname) do
      json(conn, %{available: available})
    end
  end

  def register(conn, _params) do
    case RegisterUser.call(conn.body_params) do
      {:ok, %{access_token: access_token, refresh_token: refresh_token}} ->
        conn
        |> put_refresh_cookie(refresh_token)
        |> put_status(:created)
        |> json(%{access_token: access_token})

      error ->
        error
    end
  end

  def login(conn, _params) do
    case LoginUser.call(conn.body_params) do
      {:ok, %{access_token: access_token, refresh_token: refresh_token}} ->
        conn
        |> put_refresh_cookie(refresh_token)
        |> json(%{access_token: access_token})

      error ->
        error
    end
  end

  def refresh(conn, _params) do
    conn = fetch_cookies(conn)
    refresh_token = conn.req_cookies[refresh_cookie_name()]

    if is_nil(refresh_token) do
      send_resp(conn, :no_content, "")
    else
      refresh_with_cookie(conn, refresh_token)
    end
  end

  defp refresh_with_cookie(conn, refresh_token) do
    case RefreshToken.call(%{refresh_token: refresh_token}) do
      {:ok, %{access_token: access_token, refresh_token: refresh_token}} ->
        conn
        |> put_refresh_cookie(refresh_token)
        |> json(%{access_token: access_token})

      error ->
        error
    end
  end

  def logout(conn, _params) do
    conn = fetch_cookies(conn)
    :ok = LogoutSession.call(conn.req_cookies[refresh_cookie_name()])

    conn
    |> delete_resp_cookie(refresh_cookie_name(), refresh_cookie_options())
    |> send_resp(:no_content, "")
  end

  def sign_out_all(conn, _params) do
    user = GuardianPlug.current_resource(conn)

    with :ok <- SignOutAllDevices.call(user) do
      conn
      |> delete_resp_cookie(refresh_cookie_name(), refresh_cookie_options())
      |> send_resp(:no_content, "")
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

  defp put_refresh_cookie(conn, token) do
    put_resp_cookie(conn, refresh_cookie_name(), token, refresh_cookie_options())
  end

  defp refresh_cookie_name, do: "milos_refresh"

  defp refresh_cookie_options do
    [
      http_only: true,
      secure: Application.get_env(:milos_training, :env) == :prod,
      same_site: "Strict",
      path: "/api/auth",
      max_age: 30 * 24 * 60 * 60
    ]
  end
end
