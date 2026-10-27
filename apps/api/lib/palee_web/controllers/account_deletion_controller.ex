defmodule PaleeWeb.AccountDeletionController do
  @moduledoc """
  ADR-211: self-service deletion of the current profile or of the whole
  login. A signed-in profile asks for it and can undo it; the emailed links
  confirm or undo it without a session; the sign-in form's "undo" signs in
  with the same credentials and cancels it.
  """
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias OpenApiSpex.Schema
  alias Palee.Application.AccountDeletion
  alias PaleeWeb.AuthController
  alias PaleeWeb.PasswordRecoveryController.Body

  action_fallback PaleeWeb.FallbackController

  tags(["Account deletion"])

  @deletion_schema %Schema{
    type: :object,
    properties: %{
      status: %Schema{type: :string, enum: ["none", "awaiting_confirmation", "scheduled"]},
      scope: %Schema{type: :string, enum: ["profile", "login"], nullable: true},
      scheduled_for: %Schema{type: :string, format: :"date-time", nullable: true},
      email: %Schema{
        type: :string,
        nullable: true,
        description: "Where the confirmation link went (awaiting_confirmation only)"
      }
    },
    required: [:status]
  }

  @error_schema %Schema{
    type: :object,
    properties: %{
      code: %Schema{type: :string},
      error: %Schema{type: :string},
      organizations: %Schema{type: :array, items: %Schema{type: :string}},
      scheduled_for: %Schema{type: :string, format: :"date-time"}
    },
    required: [:error]
  }

  @token_body Body.json(%{token: %Schema{type: :string, minLength: 20, maxLength: 256}}, [:token])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [:create, :confirm, :undo, :undo_sign_in]

  operation(:show,
    summary: "The login's open deletion request",
    responses: [ok: {"Deletion state", "application/json", @deletion_schema}]
  )

  operation(:create,
    summary: "Ask to delete the current profile or the whole login",
    description:
      "Needs the password. A verified email gets a confirmation link; otherwise `confirm_email` (the login's email, typed) schedules it at once and the session ends.",
    request_body:
      Body.json(
        %{
          scope: %Schema{type: :string, enum: ["profile", "login"]},
          password: %Schema{type: :string, minLength: 1},
          confirm_email: %Schema{type: :string}
        },
        [:scope, :password]
      ),
    responses: [
      accepted: {"Awaiting the emailed link, or scheduled", "application/json", @deletion_schema},
      conflict:
        {"Sole owner of a business, or already scheduled", "application/json", @error_schema},
      unprocessable_entity: {"Wrong password or confirmation", "application/json", @error_schema},
      too_many_requests: {"Rate limited", "application/json", @error_schema}
    ]
  )

  operation(:delete,
    summary: "Undo the login's deletion request from a signed-in profile",
    responses: [
      no_content: {"Cancelled", nil, nil},
      not_found: {"None open", "application/json", @error_schema}
    ]
  )

  operation(:confirm,
    summary: "Confirm a deletion with the emailed link",
    request_body: @token_body,
    responses: [
      ok: {"Scheduled", "application/json", @deletion_schema},
      unprocessable_entity: {"Invalid or used link", "application/json", @error_schema},
      gone: {"Expired link", "application/json", @error_schema}
    ]
  )

  operation(:undo,
    summary: "Undo a scheduled deletion with the emailed link",
    request_body: @token_body,
    responses: [
      ok: {"Cancelled", "application/json", @deletion_schema},
      unprocessable_entity: {"Invalid or used link", "application/json", @error_schema},
      gone: {"Expired link", "application/json", @error_schema}
    ]
  )

  operation(:undo_sign_in,
    summary: "Undo a scheduled deletion and sign in",
    request_body:
      Body.json(
        %{
          identifier: %Schema{
            type: :string,
            description: "The login's email or a profile's @handle"
          },
          password: %Schema{type: :string, minLength: 1}
        },
        [:identifier, :password]
      ),
    responses: [
      ok:
        {"Access session", "application/json",
         %Schema{
           type: :object,
           properties: %{access_token: %Schema{type: :string}, user: %Schema{type: :object}},
           required: [:access_token]
         }},
      unauthorized: {"Wrong credentials", "application/json", @error_schema}
    ]
  )

  def show(conn, _params) do
    with {:ok, summary} <- AccountDeletion.status(GuardianPlug.current_resource(conn)) do
      json(conn, summary_json(summary))
    end
  end

  def create(conn, _params) do
    account = GuardianPlug.current_resource(conn)

    with {:ok, summary} <- AccountDeletion.request(account, conn.body_params) do
      conn
      |> put_status(:accepted)
      |> json(
        summary
        |> summary_json()
        |> Map.put(:email, if(summary.status == :awaiting_confirmation, do: account.email))
      )
    end
  end

  def delete(conn, _params) do
    with :ok <- AccountDeletion.cancel(GuardianPlug.current_resource(conn)) do
      send_resp(conn, :no_content, "")
    end
  end

  def confirm(conn, _params) do
    with {:ok, summary} <- AccountDeletion.confirm(conn.body_params.token) do
      json(conn, summary_json(summary))
    end
  end

  def undo(conn, _params) do
    with {:ok, summary} <- AccountDeletion.cancel_by_link(conn.body_params.token) do
      json(conn, summary_json(summary))
    end
  end

  def undo_sign_in(conn, _params) do
    case AccountDeletion.cancel_with_credentials(conn.body_params) do
      {:ok, %{access_token: access_token, refresh_token: refresh_token, user: user}} ->
        conn
        |> AuthController.put_refresh_cookie(refresh_token)
        |> json(%{access_token: access_token, user: AuthController.current_user_json(user)})

      error ->
        error
    end
  end

  defp summary_json(summary) do
    %{
      status: Atom.to_string(summary.status),
      scope: summary |> Map.get(:scope) |> then(&(&1 && Atom.to_string(&1))),
      scheduled_for: Map.get(summary, :scheduled_for)
    }
  end
end
