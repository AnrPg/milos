defmodule MilosTrainingWeb.MeController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{SearchUsers, UpdateAvatar, UpdateProfile}
  alias MilosTraining.Infrastructure.Storage.MinioStorage
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Me"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:update_profile]

  operation(:update_profile,
    summary: "Update current user profile (nickname, password, avatar_url)",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              nickname: %Schema{type: :string, minLength: 3, maxLength: 30},
              current_password: %Schema{type: :string},
              password: %Schema{type: :string, minLength: 8},
              avatar_url: %Schema{type: :string, nullable: true}
            }
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
             user: %Schema{
               type: :object,
               properties: %{
                 id: %Schema{type: :string, format: :uuid},
                 nickname: %Schema{type: :string},
                 role: %Schema{type: :string},
                 avatar_url: %Schema{type: :string, nullable: true}
               }
             }
           }
         }},
      unprocessable_entity: {"Validation errors", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:avatar_upload_url,
    summary: "Get a presigned URL for avatar upload",
    responses: [
      ok:
        {"Upload URL", "application/json",
         %Schema{
           type: :object,
           properties: %{
             upload_url: %Schema{type: :string},
             public_url: %Schema{type: :string},
             key: %Schema{type: :string}
           }
         }}
    ]
  )

  operation(:update_avatar,
    summary: "Update current user avatar URL",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            required: [:avatar_url],
            properties: %{
              avatar_url: %Schema{type: :string, nullable: true}
            }
          }
        }
      }
    },
    responses: [
      ok:
        {"Updated avatar", "application/json",
         %Schema{
           type: :object,
           properties: %{
             user: %Schema{
               type: :object,
               properties: %{
                 id: %Schema{type: :string, format: :uuid},
                 avatar_url: %Schema{type: :string, nullable: true}
               }
             }
           }
         }},
      unprocessable_entity: {"Validation errors", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:search_users,
    summary: "Search all users by nickname",
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
        {"User search results", "application/json",
         %Schema{
           type: :object,
           properties: %{
             users: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   id: %Schema{type: :string, format: :uuid},
                   nickname: %Schema{type: :string},
                   role: %Schema{type: :string}
                 }
               }
             }
           }
         }}
    ]
  )

  def update_profile(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    params = conn.body_params

    with {:ok, updated_user} <- UpdateProfile.call(user, params) do
      json(conn, %{
        user: %{
          id: updated_user.id,
          nickname: updated_user.nickname,
          role: to_string(updated_user.role),
          avatar_url: updated_user.avatar_url
        }
      })
    end
  end

  def update_avatar(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    avatar_url = conn.body_params["avatar_url"]

    with {:ok, updated_user} <- UpdateAvatar.call(user.id, avatar_url) do
      json(conn, %{user: %{id: updated_user.id, avatar_url: updated_user.avatar_url}})
    end
  end

  def avatar_upload_url(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, result} <- MinioStorage.presigned_avatar_upload_url(user.id) do
      json(conn, result)
    end
  end

  def search_users(conn, params) do
    query = params["q"] || ""
    users = SearchUsers.call(query)

    json(conn, %{
      users:
        Enum.map(users, fn u ->
          %{id: u.id, nickname: u.nickname, role: to_string(u.role)}
        end)
    })
  end
end
