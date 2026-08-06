defmodule MilosTrainingWeb.MeController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    RequestAvatarUpload,
    ResolvePlatformContext,
    ResolveTenantContext,
    SearchUsers,
    UpdateAvatar,
    UpdateProfile
  }

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Me"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [:update_profile, :avatar_upload_url, :update_avatar]

  operation(:update_profile,
    summary: "Update current user profile and language preference",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              nickname: %Schema{type: :string, minLength: 3, maxLength: 30},
              current_password: %Schema{type: :string},
              password: %Schema{type: :string, minLength: 4},
              preferred_locale: %Schema{
                type: :string,
                enum: MilosTraining.Identity.supported_locales()
              }
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
                 avatar_url: %Schema{type: :string, nullable: true},
                 preferred_locale: %Schema{type: :string}
               }
             }
           }
         }},
      unprocessable_entity: {"Validation errors", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:avatar_upload_url,
    summary: "Create a constrained presigned avatar upload",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            required: [:content_type, :byte_size],
            properties: %{
              content_type: %Schema{
                type: :string,
                enum: [
                  "image/jpeg",
                  "image/png",
                  "image/webp",
                  "image/gif",
                  "image/bmp",
                  "image/avif"
                ]
              },
              byte_size: %Schema{type: :integer, minimum: 1, maximum: 5_242_880}
            }
          }
        }
      }
    },
    responses: [
      ok:
        {"Upload URL", "application/json",
         %Schema{
           type: :object,
           properties: %{
             upload_url: %Schema{type: :string},
             key: %Schema{type: :string},
             required_headers: %Schema{type: :object},
             expires_in: %Schema{type: :integer},
             max_bytes: %Schema{type: :integer}
           }
         }}
    ]
  )

  operation(:update_avatar,
    summary: "Finalize or clear the current user's avatar",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            required: [:avatar_key],
            properties: %{
              avatar_key: %Schema{type: :string, nullable: true}
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
    summary: "Search visible users by nickname",
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
          avatar_url: updated_user.avatar_url,
          preferred_locale: updated_user.preferred_locale
        }
      })
    end
  end

  def update_avatar(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, avatar_key} <- avatar_key_param(conn.body_params),
         {:ok, updated_user} <- UpdateAvatar.call(user.id, avatar_key) do
      json(conn, %{user: %{id: updated_user.id, avatar_url: updated_user.avatar_url}})
    end
  end

  defp avatar_key_param(%{avatar_key: avatar_key}), do: {:ok, avatar_key}
  defp avatar_key_param(%{"avatar_key" => avatar_key}), do: {:ok, avatar_key}
  defp avatar_key_param(_params), do: {:error, :invalid_avatar_upload}

  def avatar_upload_url(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, result} <- RequestAvatarUpload.call(user.id, conn.body_params) do
      json(conn, result)
    end
  end

  def search_users(conn, params) do
    user = Guardian.Plug.current_resource(conn)
    query = params["q"] || ""

    with {:ok, users} <- search_visible_users(conn, user, query) do
      json(conn, %{
        users:
          Enum.map(users, fn u ->
            %{id: u.id, nickname: u.nickname, role: to_string(u.role)}
          end)
      })
    end
  end

  defp search_visible_users(conn, user, query) do
    if vendor?(user) do
      {:ok, SearchUsers.call(query)}
    else
      case conn.assigns[:tenant_context] do
        nil ->
          with {:ok, slug} <- organization_slug(conn),
               {:ok, tenant_context} <-
                 ResolveTenantContext.call(user, slug, request_metadata(conn)) do
            {:ok, SearchUsers.call(query, tenant_context)}
          end

        tenant_context ->
          {:ok, SearchUsers.call(query, tenant_context)}
      end
    end
  end

  defp vendor?(user) do
    match?({:ok, _context}, ResolvePlatformContext.call(user, %{}))
  end

  defp organization_slug(conn) do
    case List.first(get_req_header(conn, "x-organization-slug")) do
      slug when is_binary(slug) and slug != "" -> {:ok, slug}
      _missing -> {:error, :organization_context_required}
    end
  end

  defp request_metadata(conn) do
    %{
      transport: :http,
      method: conn.method,
      request_id: List.first(get_resp_header(conn, "x-request-id"))
    }
  end
end
