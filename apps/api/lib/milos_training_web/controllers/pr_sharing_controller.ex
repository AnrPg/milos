defmodule MilosTrainingWeb.PRSharingController do
  @moduledoc """
  ADR-129 personal PR sharing: the coach-visibility opt-out, explicit
  read-only grants to other accounts, and the grantee's "Shared with me" view.
  User-scoped (not tenant-scoped): grants and the opt-out are global personal
  data that apply across every gym.
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    FindPRGrantee,
    GetPRSharing,
    GrantPRAccess,
    ListPRsSharedWithMe,
    RevokePRAccess,
    SetPRCoachVisibility
  }

  alias OpenApiSpex.{Parameter, Schema}

  action_fallback(MilosTrainingWeb.FallbackController)

  tags(["Pantheon"])
  security([%{"bearerAuth" => []}])

  @uuid %Schema{type: :string, format: :uuid}

  @profile %Schema{
    type: :object,
    required: [:id, :nickname, :display_nickname],
    properties: %{
      id: @uuid,
      nickname: %Schema{type: :string},
      display_nickname: %Schema{type: :string},
      avatar_url: %Schema{type: :string, nullable: true}
    }
  }

  @grant %Schema{
    type: :object,
    required: [:id, :created_at, :grantee],
    properties: %{
      id: @uuid,
      created_at: %Schema{type: :string, format: :"date-time"},
      grantee: @profile
    }
  }

  @sharing %Schema{
    type: :object,
    required: [:coach_visibility, :grants],
    properties: %{
      coach_visibility: %Schema{
        type: :boolean,
        description:
          "When true (default), coaches of the gym a PR was recorded in can read it while you are an active member there."
      },
      grants: %Schema{type: :array, items: @grant}
    }
  }

  @history_entry %Schema{
    type: :object,
    required: [:id, :score, :beaten_on],
    properties: %{
      id: @uuid,
      score: %Schema{type: :number},
      beaten_on: %Schema{type: :string, format: :date},
      supporting_metrics: %Schema{type: :object, additionalProperties: true},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    }
  }

  @shared_pr %Schema{
    type: :object,
    required: [:id, :name, :current_score, :unit, :higher_is_better, :beaten_on, :history],
    properties: %{
      id: @uuid,
      organization_id: %Schema{type: :string, format: :uuid, nullable: true},
      name: %Schema{type: :string},
      current_score: %Schema{type: :number},
      unit: %Schema{type: :string},
      higher_is_better: %Schema{type: :boolean},
      beaten_on: %Schema{type: :string, format: :date},
      supporting_metrics: %Schema{type: :object, additionalProperties: true},
      updated_at: %Schema{type: :string, format: :"date-time"},
      history: %Schema{type: :array, items: @history_entry}
    }
  }

  @shared_with_me %Schema{
    type: :object,
    required: [:shared],
    properties: %{
      shared: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          required: [:grant_id, :shared_at, :owner, :prs],
          properties: %{
            grant_id: @uuid,
            shared_at: %Schema{type: :string, format: :"date-time"},
            owner: @profile,
            prs: %Schema{type: :array, items: @shared_pr}
          }
        }
      }
    }
  }

  @error %Schema{type: :object, additionalProperties: true}

  operation(:show,
    summary: "Get my PR sharing settings",
    responses: [ok: {"PR sharing settings", "application/json", @sharing}]
  )

  def show(conn, _params) do
    with {:ok, sharing} <- GetPRSharing.call(conn.assigns.user_context) do
      json(conn, sharing)
    end
  end

  operation(:update_coach_visibility,
    summary: "Allow or stop gym coaches reading my PRs",
    request_body:
      {"Coach visibility", "application/json",
       %Schema{
         type: :object,
         required: [:coach_visibility],
         properties: %{coach_visibility: %Schema{type: :boolean}}
       }},
    responses: [
      ok: {"PR sharing settings", "application/json", @sharing},
      bad_request: {"Error", "application/json", @error}
    ]
  )

  def update_coach_visibility(conn, params) do
    with {:ok, sharing} <- SetPRCoachVisibility.call(conn.assigns.user_context, params) do
      json(conn, sharing)
    end
  end

  operation(:create_grant,
    summary: "Share all my PRs (read-only) with another account",
    request_body:
      {"Grant", "application/json",
       %Schema{
         type: :object,
         required: [:grantee_user_id],
         properties: %{grantee_user_id: @uuid}
       }},
    responses: [
      created: {"Grant", "application/json", @grant},
      bad_request: {"Error", "application/json", @error},
      not_found: {"Error", "application/json", @error},
      unprocessable_entity: {"Error", "application/json", @error}
    ]
  )

  def create_grant(conn, params) do
    with {:ok, grant} <- GrantPRAccess.call(conn.assigns.user_context, params) do
      conn
      |> put_status(:created)
      |> json(grant)
    end
  end

  operation(:revoke_grant,
    summary: "Stop sharing my PRs with an account",
    parameters: [
      %Parameter{name: :id, in: :path, required: true, description: "Grant ID", schema: @uuid}
    ],
    responses: [
      no_content: {"Revoked", "application/json", @error},
      not_found: {"Error", "application/json", @error}
    ]
  )

  def revoke_grant(conn, %{"id" => id}) do
    with :ok <- RevokePRAccess.call(conn.assigns.user_context, id) do
      send_resp(conn, :no_content, "")
    end
  end

  operation(:lookup_grantee,
    summary: "Find an account to share my PRs with by its exact nickname (ADR-132)",
    description:
      "Exact, normalized nickname match only (no prefix or fuzzy search), so accounts cannot be enumerated. Returns the account id and nickname, nothing else; `grantee` is null for an unknown nickname or for yourself.",
    parameters: [
      %Parameter{
        name: :nickname,
        in: :query,
        required: true,
        schema: %Schema{type: :string, maxLength: 64}
      }
    ],
    responses: [
      ok:
        {"Grantee lookup", "application/json",
         %Schema{
           type: :object,
           required: [:grantee],
           properties: %{
             grantee: %Schema{
               type: :object,
               nullable: true,
               required: [:id, :nickname, :display_nickname],
               properties: %{
                 id: @uuid,
                 nickname: %Schema{type: :string},
                 display_nickname: %Schema{type: :string}
               }
             }
           }
         }},
      bad_request: {"Error", "application/json", @error}
    ]
  )

  def lookup_grantee(conn, params) do
    with {:ok, result} <- FindPRGrantee.call(conn.assigns.user_context, params["nickname"]) do
      json(conn, result)
    end
  end

  operation(:shared_with_me,
    summary: "PRs other accounts have shared with me",
    responses: [ok: {"Shared PRs", "application/json", @shared_with_me}]
  )

  def shared_with_me(conn, _params) do
    with {:ok, shared} <- ListPRsSharedWithMe.call(conn.assigns.user_context) do
      json(conn, shared)
    end
  end
end
