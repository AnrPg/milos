defmodule PaleeWeb.MeController do
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.CompleteProductTour

  alias Palee.Application.{
    ReportTimeZone,
    RequestAvatarUpload,
    ResolvePlatformContext,
    ResolveTenantContext,
    SearchUsers,
    UpdateAvatar,
    UpdateProfile
  }

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Me"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [:update_profile, :avatar_upload_url, :update_avatar, :update_time_zone]

  operation(:complete_tour,
    summary: "Record that the current account finished a product tour",
    parameters: [
      %Parameter{
        name: :audience,
        in: :path,
        required: true,
        schema: %Schema{type: :string, enum: Palee.Identity.tour_audiences()}
      }
    ],
    responses: [
      ok:
        {"Completed tours", "application/json",
         %Schema{
           type: :object,
           properties: %{completed_tours: %Schema{type: :array, items: %Schema{type: :string}}},
           required: [:completed_tours]
         }}
    ]
  )

  def complete_tour(conn, %{"audience" => audience}) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, account} <- CompleteProductTour.call(user, audience) do
      json(conn, %{completed_tours: account.completed_tours})
    end
  end

  operation(:update_time_zone,
    summary: "Report the zone this account's device is in (ADR-179)",
    description:
      "Server-written texts add the reader's own time beside the organiser's when the two zones read a moment differently. UTC aliases are ignored.",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{time_zone: %Schema{type: :string, maxLength: 100}},
            required: [:time_zone]
          }
        }
      }
    },
    responses: [
      ok:
        {"Stored zone", "application/json",
         %Schema{
           type: :object,
           properties: %{time_zone: %Schema{type: :string, nullable: true}},
           required: [:time_zone]
         }}
    ]
  )

  def update_time_zone(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, zone} <- ReportTimeZone.call(user, Map.get(conn.body_params, :time_zone)) do
      json(conn, %{time_zone: zone})
    end
  end

  operation(:update_profile,
    summary: "Update current user profile and language preference",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              handle: %Schema{
                type: :string,
                description: "ADR-187: the unique @handle (once per 14 days)"
              },
              display_name: %Schema{type: :string, minLength: 1, maxLength: 50},
              nickname: %Schema{type: :string, description: "Deprecated alias of display_name"},
              current_password: %Schema{
                type: :string,
                description: "Required to change the login's email or password"
              },
              password: %Schema{type: :string, minLength: 4},
              email: %Schema{
                type: :string,
                format: :email,
                nullable: true,
                description:
                  "ADR-207: only the current address; a new one goes through /api/me/email-change"
              },
              preferred_locale: %Schema{
                type: :string,
                enum: Palee.Identity.supported_locales()
              },
              preferred_theme_slug: %Schema{
                type: :string,
                nullable: true,
                enum: Palee.Themes.slugs() ++ [nil],
                description: "Your own theme: graphite (dark) or frost (light); null is frost"
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
                 display_name: %Schema{type: :string},
                 handle: %Schema{type: :string},
                 email: %Schema{type: :string},
                 role: %Schema{type: :string},
                 avatar_url: %Schema{type: :string, nullable: true},
                 preferred_locale: %Schema{type: :string},
                 preferred_theme_slug: %Schema{type: :string, nullable: true}
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
    summary: "Search visible users by @handle or display name (any script)",
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
                   handle: %Schema{type: :string},
                   avatar_url: %Schema{type: :string, nullable: true},
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

    case UpdateProfile.call(user, params) do
      {:ok, updated_user} ->
        render_profile(conn, updated_user)

      # ADR-207: a new address goes through POST /api/me/email-change.
      {:error, :email_change_needs_confirmation} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          code: "email_change_needs_confirmation",
          error: "Change the email from Settings: the new address confirms it by a link"
        })

      error ->
        error
    end
  end

  defp render_profile(conn, updated_user) do
    json(conn, %{
      user: %{
        id: updated_user.id,
        nickname: updated_user.nickname,
        display_name: updated_user.nickname,
        handle: updated_user.handle,
        email: updated_user.email,
        role: to_string(updated_user.role),
        avatar_url: updated_user.avatar_url,
        preferred_locale: updated_user.preferred_locale,
        preferred_theme_slug: updated_user.preferred_theme_slug
      }
    })
  end

  def update_avatar(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, avatar_key} <- avatar_key_param(conn.body_params),
         {:ok, updated_user} <- UpdateAvatar.call(user.id, avatar_key) do
      json(conn, %{user: %{id: updated_user.id, avatar_url: updated_user.avatar_url}})
    end
  end

  # OpenApiSpex casting replaces body_params with an atom-keyed map, which
  # Plug's string-keyed body_params type does not model; Map.fetch/2 keeps
  # both shapes reachable for Dialyzer.
  defp avatar_key_param(params) do
    with :error <- Map.fetch(params, :avatar_key),
         :error <- Map.fetch(params, "avatar_key") do
      {:error, :invalid_avatar_upload}
    end
  end

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
            %{
              id: u.id,
              nickname: u.nickname,
              handle: Map.get(u, :handle),
              avatar_url: Map.get(u, :avatar_url),
              role: to_string(u.role)
            }
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
