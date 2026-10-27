defmodule PaleeWeb.EmailChangeController do
  @moduledoc """
  ADR-207: changing the login's email by a link to the new address.

  Signed in (`/api/me/email-change`): see, start, resend or cancel the
  pending change. Public (`/api/auth/email-change/*`): the confirmation
  link and the old address's "this wasn't me" link.

  Confirming revokes every session of every profile. When the browser that
  opens the link holds a session of the same login (its refresh cookie,
  which reaches `/api/auth`), it gets a fresh session for that profile, so
  the person who confirms stays signed in there; every other device signs
  in again with the new address.
  """
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias OpenApiSpex.Schema
  alias Palee.Application.{EmailChange, TokenIssuer, TokenVerifier}
  alias Palee.Identity
  alias PaleeWeb.AuthController
  alias PaleeWeb.PasswordRecoveryController.Body

  action_fallback PaleeWeb.FallbackController

  tags(["Email change"])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [:create, :confirm, :revert]

  @status_schema %Schema{
    type: :object,
    properties: %{
      pending: %Schema{
        type: :object,
        nullable: true,
        properties: %{
          email: %Schema{type: :string},
          requested_at: %Schema{type: :string, format: :"date-time"},
          expires_at: %Schema{type: :string, format: :"date-time"}
        },
        required: [:email, :requested_at, :expires_at]
      },
      locked_until: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:pending, :locked_until]
  }

  @error_schema %Schema{
    type: :object,
    properties: %{
      code: %Schema{type: :string},
      error: %Schema{type: :string},
      locked_until: %Schema{type: :string, format: :"date-time"}
    }
  }

  operation(:show,
    summary: "The login's pending email change, if any",
    security: [%{"bearerAuth" => []}],
    responses: [ok: {"Status", "application/json", @status_schema}]
  )

  def show(conn, _params) do
    json(conn, render_status(EmailChange.status(GuardianPlug.current_resource(conn))))
  end

  operation(:create,
    summary: "Ask to change the login's email (needs the current password)",
    description:
      "Mails a 24 h link to the new address; the login keeps its email until it is opened. " <>
        "The answer is the same whether or not the address already has an account.",
    security: [%{"bearerAuth" => []}],
    request_body:
      Body.json(%{email: %Schema{type: :string}, current_password: %Schema{type: :string}}, [
        :email,
        :current_password
      ]),
    responses: [
      accepted: {"Pending", "application/json", @status_schema},
      unprocessable_entity:
        {"Wrong current password, or an invalid or unchanged address", "application/json",
         @error_schema},
      conflict: {"Changes are locked for now", "application/json", @error_schema},
      too_many_requests: {"Sent just now", "application/json", @error_schema}
    ]
  )

  def create(conn, _params) do
    body = conn.body_params

    case EmailChange.request(
           GuardianPlug.current_resource(conn),
           body.email,
           body.current_password
         ) do
      {:ok, status} -> conn |> put_status(:accepted) |> json(render_status(status))
      error -> respond_error(conn, error)
    end
  end

  operation(:resend,
    summary: "Mail the pending change's link again",
    security: [%{"bearerAuth" => []}],
    responses: [
      ok: {"Pending", "application/json", @status_schema},
      not_found: {"Nothing pending", "application/json", @error_schema},
      too_many_requests: {"Sent just now", "application/json", @error_schema}
    ]
  )

  def resend(conn, _params) do
    case EmailChange.resend(GuardianPlug.current_resource(conn)) do
      {:ok, status} -> json(conn, render_status(status))
      error -> respond_error(conn, error)
    end
  end

  operation(:delete,
    summary: "Cancel the pending email change",
    security: [%{"bearerAuth" => []}],
    responses: [ok: {"Status", "application/json", @status_schema}]
  )

  def delete(conn, _params) do
    account = GuardianPlug.current_resource(conn)
    :ok = EmailChange.cancel(account)
    json(conn, render_status(EmailChange.status(account)))
  end

  operation(:confirm,
    summary: "Open the link mailed to the new address",
    description:
      "Every session of every profile ends. A browser holding a session of the same login " <>
        "gets a fresh one (access_token in the answer, refresh cookie).",
    request_body: Body.json(%{token: %Schema{type: :string}}, [:token]),
    responses: [
      ok:
        {"Changed", "application/json",
         %Schema{
           type: :object,
           properties: %{
             email: %Schema{type: :string},
             access_token: %Schema{type: :string, nullable: true},
             user: %Schema{type: :object, nullable: true}
           },
           required: [:email, :access_token]
         }},
      unprocessable_entity: {"Unknown or used link", "application/json", @error_schema},
      gone: {"Expired link", "application/json", @error_schema},
      conflict: {"Address no longer available", "application/json", @error_schema}
    ]
  )

  def confirm(conn, _params) do
    # Read before confirming: the change revokes the session it proves.
    session_user = refresh_cookie_user(conn)

    case EmailChange.confirm(conn.body_params.token) do
      {:ok, %{login_id: login_id, email: email}} ->
        conn
        |> maybe_fresh_session(session_user, login_id)
        |> then(fn {conn, session} -> json(conn, Map.put(session, :email, email)) end)

      error ->
        respond_error(conn, error)
    end
  end

  operation(:revert,
    summary: "\"This wasn't me\": put the old address back and lock email changes",
    request_body: Body.json(%{token: %Schema{type: :string}}, [:token]),
    responses: [
      ok:
        {"Reverted", "application/json",
         %Schema{type: :object, properties: %{email: %Schema{type: :string}}, required: [:email]}},
      unprocessable_entity: {"Unknown or used link", "application/json", @error_schema},
      gone: {"Expired link", "application/json", @error_schema},
      conflict: {"Address no longer available", "application/json", @error_schema}
    ]
  )

  def revert(conn, _params) do
    case EmailChange.revert(conn.body_params.token) do
      {:ok, %{email: email}} -> json(conn, %{email: email})
      error -> respond_error(conn, error)
    end
  end

  defp refresh_cookie_user(conn) do
    conn = fetch_cookies(conn)

    with token when is_binary(token) <- conn.req_cookies["palee_refresh"],
         {:ok, claims} <- TokenVerifier.decode_refresh_token(token),
         {:ok, user} <- TokenVerifier.user_from_claims(claims) do
      user
    else
      _no_session -> nil
    end
  end

  defp maybe_fresh_session(conn, %{id: user_id, login_id: login_id}, login_id) do
    with %{} = user <- Identity.find_by_id(user_id),
         {:ok, %{access_token: access, refresh_token: refresh}} <- TokenIssuer.issue_pair(user) do
      {AuthController.put_refresh_cookie(conn, refresh),
       %{access_token: access, user: AuthController.current_user_json(user)}}
    else
      _failed -> {conn, %{access_token: nil}}
    end
  end

  defp maybe_fresh_session(conn, _session_user, _login_id), do: {conn, %{access_token: nil}}

  defp render_status(%{pending: pending, locked_until: locked_until}),
    do: %{pending: pending, locked_until: locked_until}

  @messages %{
    invalid_email: {:unprocessable_entity, "Enter a valid email address"},
    email_unchanged: {:unprocessable_entity, "This is already your email address"},
    no_pending_email_change: {:not_found, "There is no email change waiting for confirmation"},
    invalid_link: {:unprocessable_entity, "This link is not valid or was already used"},
    expired_link: {:gone, "This link has expired"},
    email_unavailable: {:conflict, "This address can't be used for your account"}
  }

  @codes %{
    invalid_link: "invalid_email_change_link",
    expired_link: "expired_email_change_link",
    email_unavailable: "email_change_unavailable"
  }

  defp respond_error(conn, {:error, {:email_change_locked, until}}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "email_change_locked",
      error: "Email changes are paused on this account for now",
      locked_until: until
    })
  end

  defp respond_error(conn, {:error, reason}) when is_map_key(@messages, reason) do
    {status, message} = Map.fetch!(@messages, reason)

    conn
    |> put_status(status)
    |> json(%{code: Map.get(@codes, reason, to_string(reason)), error: message})
  end

  defp respond_error(_conn, error), do: error
end
