defmodule PaleeWeb.AccountProfilesController do
  @moduledoc """
  ADR-187: the up to three profiles of the signed-in person's login. A
  session of any of them is the proof of owning the email, so only then are
  the profiles listed, added or switched to.
  """
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias OpenApiSpex.{RequestBody, Schema}
  alias Palee.Application.AccountProfiles
  alias PaleeWeb.AuthController

  action_fallback PaleeWeb.FallbackController

  tags(["Authentication"])

  @profile_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      handle: %Schema{type: :string},
      display_name: %Schema{type: :string},
      avatar_url: %Schema{type: :string, nullable: true},
      role: %Schema{type: :string},
      current: %Schema{type: :boolean}
    },
    required: [:id, :handle, :display_name, :role, :current]
  }

  @profiles_schema %Schema{
    type: :object,
    properties: %{
      email: %Schema{type: :string},
      profile_limit: %Schema{type: :integer},
      profiles: %Schema{type: :array, items: @profile_schema}
    },
    required: [:email, :profile_limit, :profiles]
  }

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [:create, :switch]

  operation(:index,
    summary: "The profiles of the signed-in login",
    security: [%{"bearerAuth" => []}],
    responses: [ok: {"Profiles", "application/json", @profiles_schema}]
  )

  operation(:create,
    summary: "Add a profile to the signed-in login (at most three)",
    security: [%{"bearerAuth" => []}],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %OpenApiSpex.MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              handle: %Schema{type: :string},
              display_name: %Schema{type: :string},
              role: %Schema{type: :string, enum: ["member", "athlete"]}
            },
            required: [:handle, :role]
          }
        }
      }
    },
    responses: [
      created: {"Profiles", "application/json", @profiles_schema},
      unprocessable_entity: {"Validation or limit", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:switch,
    summary: "Open a session for another profile of the same login",
    security: [%{"bearerAuth" => []}],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %OpenApiSpex.MediaType{
          schema: %Schema{
            type: :object,
            properties: %{user_id: %Schema{type: :string, format: :uuid}},
            required: [:user_id]
          }
        }
      }
    },
    responses: [
      ok:
        {"Access session", "application/json",
         %Schema{
           type: :object,
           properties: %{access_token: %Schema{type: :string}, user: %Schema{type: :object}},
           required: [:access_token, :user]
         }},
      not_found: {"Not a profile of this login", "application/json", %Schema{type: :object}}
    ]
  )

  def index(conn, _params) do
    account = GuardianPlug.current_resource(conn)

    with {:ok, profiles} <- AccountProfiles.list(account) do
      json(conn, profiles_json(account, profiles))
    end
  end

  def create(conn, _params) do
    account = GuardianPlug.current_resource(conn)

    with {:ok, _profile} <- AccountProfiles.add(account, conn.body_params),
         {:ok, profiles} <- AccountProfiles.list(account) do
      conn
      |> put_status(:created)
      |> json(profiles_json(account, profiles))
    end
  end

  def switch(conn, _params) do
    account = GuardianPlug.current_resource(conn)
    target_id = Map.get(conn.body_params, :user_id) || Map.get(conn.body_params, "user_id")

    with {:ok, %{access_token: access, refresh_token: refresh, user: user}} <-
           AccountProfiles.switch(account, target_id) do
      conn
      |> AuthController.put_refresh_cookie(refresh)
      |> json(%{access_token: access, user: AuthController.current_user_json(user)})
    end
  end

  defp profiles_json(account, profiles) do
    %{
      email: account.email,
      profile_limit: Palee.Identity.max_profiles(),
      profiles:
        Enum.map(profiles, fn profile ->
          %{
            id: profile.id,
            handle: profile.handle,
            display_name: profile.nickname,
            avatar_url: profile.avatar_url,
            role: to_string(profile.role),
            current: profile.id == account.id
          }
        end)
    }
  end
end
