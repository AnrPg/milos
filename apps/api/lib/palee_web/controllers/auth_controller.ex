defmodule PaleeWeb.AuthController do
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{
    AccountProfiles,
    LoginUser,
    LogoutSession,
    NicknameAvailability,
    RefreshToken,
    RegisterInvitedUser,
    RegisterUser,
    ResolvePlatformContext,
    SignOutAllDevices
  }

  alias Guardian.Plug, as: GuardianPlug
  alias OpenApiSpex.{RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  # ADR-178: returned by /auth/me, and with the tokens from login and refresh
  # so opening the app needs no separate /auth/me round trip.
  @current_user_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      nickname: %Schema{
        type: :string,
        description: "ADR-187: the display name (free, not unique); same as display_name"
      },
      display_name: %Schema{type: :string},
      handle: %Schema{type: :string, description: "ADR-187: the unique @handle"},
      email: %Schema{type: :string, description: "The login's email, shared by its profiles"},
      profile_count: %Schema{type: :integer},
      profile_limit: %Schema{type: :integer},
      role: %Schema{type: :string},
      avatar_url: %Schema{type: :string, nullable: true},
      vendor: %Schema{type: :boolean},
      preferred_locale: %Schema{
        type: :string,
        enum: Palee.Identity.supported_locales()
      },
      preferred_theme_slug: %Schema{
        type: :string,
        nullable: true,
        enum: Palee.Themes.slugs() ++ [nil],
        description: "The member's own theme: graphite (dark) or frost (light); null is frost"
      },
      time_zone: %Schema{
        type: :string,
        nullable: true,
        description: "ADR-179: the zone this account's device last reported"
      },
      completed_tours: %Schema{
        type: :array,
        items: %Schema{type: :string, enum: Palee.Identity.tour_audiences()}
      }
    },
    required: [
      :id,
      :nickname,
      :display_name,
      :handle,
      :role,
      :vendor,
      :preferred_locale,
      :completed_tours
    ]
  }

  # ADR-195: the language the signed-out pages were shown in becomes the new
  # profile's language, so the first signed-in screen does not switch back.
  @preferred_locale_param %Schema{
    type: :string,
    enum: Palee.Identity.supported_locales(),
    description: "ADR-195: the new profile's UI language; defaults to en"
  }

  @email_in_use_schema %Schema{
    type: :object,
    description:
      "ADR-187: the email holds profiles and the password is not theirs; only the count is disclosed",
    properties: %{
      code: %Schema{type: :string},
      error: %Schema{type: :string},
      profile_count: %Schema{type: :integer},
      profile_limit: %Schema{type: :integer}
    },
    required: [:code]
  }

  tags(["Authentication"])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [
              :register,
              :register_admin,
              :register_member,
              :login,
              :refresh,
              :nickname_available,
              :handle_available,
              :handle_suggestion
            ]

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
              handle: %Schema{type: :string, description: "ADR-187: the unique @handle"},
              nickname: %Schema{type: :string, description: "Deprecated alias of handle"},
              display_name: %Schema{
                type: :string,
                description: "Free display name; defaults to the handle"
              },
              password: %Schema{type: :string, minLength: 4},
              role: %Schema{type: :string, enum: ["member", "athlete"]},
              email: %Schema{type: :string, format: :email},
              preferred_locale: @preferred_locale_param
            },
            required: [:password, :role, :email]
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
      conflict: {"Email already has accounts", "application/json", @email_in_use_schema},
      unprocessable_entity:
        {"Validation errors", "application/json",
         %Schema{
           type: :object,
           properties: %{
             code: %Schema{type: :string},
             profile_limit: %Schema{type: :integer},
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
              identifier: %Schema{
                type: :string,
                description: "ADR-187: the login's email or a profile's @handle"
              },
              nickname: %Schema{type: :string, description: "Deprecated alias of identifier"},
              password: %Schema{type: :string, minLength: 4}
            },
            required: [:password]
          }
        }
      }
    },
    responses: [
      ok:
        {"Access session", "application/json",
         %Schema{
           type: :object,
           properties: %{access_token: %Schema{type: :string}, user: @current_user_schema},
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

  operation(:register_admin,
    summary: "Register through an owner or admin organization invitation",
    request_body: %RequestBody{
      description: "Admin registration params",
      required: true,
      content: %{
        "application/json" => %OpenApiSpex.MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              handle: %Schema{type: :string},
              nickname: %Schema{type: :string, description: "Deprecated alias of handle"},
              display_name: %Schema{type: :string},
              password: %Schema{type: :string, minLength: 4},
              invitation_token: %Schema{type: :string, minLength: 20, maxLength: 256},
              email: %Schema{type: :string, format: :email},
              preferred_locale: @preferred_locale_param
            },
            required: [:password, :invitation_token, :email]
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
      not_found:
        {"Invalid invitation", "application/json",
         %Schema{
           type: :object,
           properties: %{
             error: %Schema{type: :string}
           },
           required: [:error]
         }},
      unprocessable_entity:
        {"Validation errors", "application/json",
         %Schema{
           type: :object,
           properties: %{
             code: %Schema{type: :string},
             errors: %Schema{
               type: :object,
               additionalProperties: %Schema{type: :array, items: %Schema{type: :string}}
             }
           },
           required: [:code, :errors]
         }},
      too_many_requests:
        {"Rate limited", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }}
    ]
  )

  operation(:register_member,
    summary: "Register through an organization invitation",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %OpenApiSpex.MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              handle: %Schema{type: :string},
              nickname: %Schema{type: :string, description: "Deprecated alias of handle"},
              display_name: %Schema{type: :string},
              password: %Schema{type: :string, minLength: 4},
              invitation_token: %Schema{type: :string, minLength: 20, maxLength: 256},
              email: %Schema{type: :string, format: :email},
              preferred_locale: @preferred_locale_param
            },
            required: [:password, :invitation_token, :email]
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
      not_found: {"Invalid invitation", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:refresh,
    summary: "Refresh an access token",
    responses: [
      ok:
        {"Access session", "application/json",
         %Schema{
           type: :object,
           properties: %{access_token: %Schema{type: :string}, user: @current_user_schema},
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

  operation(:handle_available,
    summary: "ADR-187: whether a typed @handle is free, its stored form, and alternatives",
    parameters: [
      %OpenApiSpex.Parameter{
        name: :handle,
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
           properties: %{
             available: %Schema{type: :boolean},
             handle: %Schema{type: :string},
             suggestions: %Schema{type: :array, items: %Schema{type: :string}}
           },
           required: [:available, :handle, :suggestions]
         }},
      bad_request: {"Not a valid handle", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:handle_suggestion,
    summary:
      "ADR-187: a free @handle suggested from a display name (null when it has no Latin form)",
    parameters: [
      %OpenApiSpex.Parameter{
        name: :display_name,
        in: :query,
        required: true,
        schema: %Schema{type: :string}
      }
    ],
    responses: [
      ok:
        {"Suggestion", "application/json",
         %Schema{
           type: :object,
           properties: %{handle: %Schema{type: :string, nullable: true}},
           required: [:handle]
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
      ok: {"Current user", "application/json", @current_user_schema},
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

  def handle_available(conn, %{handle: handle}) do
    with {:ok, result} <- AccountProfiles.handle_availability(handle) do
      json(conn, result)
    end
  end

  def handle_suggestion(conn, %{display_name: display_name}) do
    json(conn, %{handle: AccountProfiles.suggest_handle(display_name)})
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

  def register_admin(conn, _params) do
    register_invited(conn, [:owner, :admin])
  end

  def register_member(conn, _params) do
    register_invited(conn, Palee.Organizations.roles())
  end

  defp register_invited(conn, allowed_roles) do
    case RegisterInvitedUser.call(conn.body_params, allowed_roles) do
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
      {:ok, %{access_token: access_token, refresh_token: refresh_token, user: user}} ->
        conn
        |> put_refresh_cookie(refresh_token)
        |> json(%{access_token: access_token, user: current_user_json(user)})

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
      {:ok, %{access_token: access_token, refresh_token: refresh_token, user: user}} ->
        conn
        |> put_refresh_cookie(refresh_token)
        |> json(%{access_token: access_token, user: current_user_json(user)})

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
    json(conn, current_user_json(GuardianPlug.current_resource(conn)))
  end

  @doc false
  def current_user_json(user) do
    profile_count =
      case Map.get(user, :login_id) do
        nil -> 1
        login_id -> length(Palee.Identity.list_profiles(login_id))
      end

    %{
      id: user.id,
      nickname: user.nickname,
      display_name: user.nickname,
      handle: Map.get(user, :handle) || Map.get(user, :normalized_nickname),
      email: Map.get(user, :email),
      profile_count: profile_count,
      profile_limit: Palee.Identity.max_profiles(),
      role: to_string(user.role),
      avatar_url: user.avatar_url,
      vendor: vendor?(user),
      preferred_locale: user.preferred_locale,
      preferred_theme_slug: Map.get(user, :preferred_theme_slug),
      time_zone: Map.get(user, :time_zone),
      completed_tours: Map.get(user, :completed_tours) || []
    }
  end

  defp vendor?(user) do
    match?({:ok, _context}, ResolvePlatformContext.call(user, %{}))
  end

  @doc false
  def put_refresh_cookie(conn, token) do
    put_resp_cookie(conn, refresh_cookie_name(), token, refresh_cookie_options())
  end

  defp refresh_cookie_name, do: "milos_refresh"

  defp refresh_cookie_options do
    [
      http_only: true,
      secure: Application.get_env(:palee, :env) == :prod,
      same_site: "Strict",
      path: "/api/auth",
      max_age: 30 * 24 * 60 * 60
    ]
  end
end
