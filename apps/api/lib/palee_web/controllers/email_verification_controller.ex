defmodule PaleeWeb.EmailVerificationController do
  @moduledoc """
  ADR-213: confirming a login's email address. `verify` is public (the link
  from the email may be opened signed out, on another device); `resend` is
  for the signed-in person.
  """
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias OpenApiSpex.{RequestBody, Schema}
  alias Palee.Application.EmailVerification

  action_fallback PaleeWeb.FallbackController

  tags(["Authentication"])

  @error_schema %Schema{
    type: :object,
    properties: %{code: %Schema{type: :string}, error: %Schema{type: :string}},
    required: [:code, :error]
  }

  @link_errors %{
    invalid: {:unprocessable_entity, "invalid_verification_link", "This link isn't valid"},
    used: {:conflict, "used_verification_link", "This link was already used"},
    expired: {:gone, "expired_verification_link", "This link has expired"},
    email_mismatch:
      {:conflict, "verification_email_changed",
       "The account's email changed after this link was sent"}
  }

  plug OpenApiSpex.Plug.CastAndValidate, [json_render_error_v2: true] when action in [:verify]

  operation(:verify,
    summary: "ADR-213: confirm the login's email with the emailed link's token",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %OpenApiSpex.MediaType{
          schema: %Schema{
            type: :object,
            properties: %{token: %Schema{type: :string, minLength: 1, maxLength: 256}},
            required: [:token]
          }
        }
      }
    },
    responses: [
      ok:
        {"Email verified", "application/json",
         %Schema{
           type: :object,
           properties: %{email_verified: %Schema{type: :boolean}},
           required: [:email_verified]
         }},
      conflict:
        {"Link already used, or the email changed since", "application/json", @error_schema},
      gone: {"Link expired", "application/json", @error_schema},
      unprocessable_entity: {"Unknown link", "application/json", @error_schema},
      too_many_requests: {"Rate limited", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:resend,
    summary: "ADR-213: email the signed-in person a new verification link",
    security: [%{"bearerAuth" => []}],
    responses: [
      ok:
        {"Sent, or nothing to do", "application/json",
         %Schema{
           type: :object,
           properties: %{status: %Schema{type: :string, enum: ["already_verified", "sent"]}},
           required: [:status]
         }},
      too_many_requests:
        {"A link was sent just now", "application/json",
         %Schema{
           type: :object,
           properties: %{
             code: %Schema{type: :string},
             error: %Schema{type: :string},
             retry_after_seconds: %Schema{type: :integer}
           },
           required: [:code, :error, :retry_after_seconds]
         }},
      unprocessable_entity: {"The address can't get email", "application/json", @error_schema},
      service_unavailable: {"Email is busy today", "application/json", @error_schema}
    ]
  )

  def verify(conn, _params) do
    case EmailVerification.verify(conn.body_params.token) do
      :ok ->
        json(conn, %{email_verified: true})

      {:error, reason} when is_map_key(@link_errors, reason) ->
        {status, code, message} = Map.fetch!(@link_errors, reason)

        conn
        |> put_status(status)
        |> json(%{code: code, error: message})
    end
  end

  def resend(conn, _params) do
    case EmailVerification.resend(GuardianPlug.current_resource(conn)) do
      {:ok, status} ->
        json(conn, %{status: Atom.to_string(status)})

      {:error, {:throttled, seconds}} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(seconds))
        |> put_status(:too_many_requests)
        |> json(%{
          code: "throttled",
          error: "A link was sent just now. Try again later",
          retry_after_seconds: seconds
        })

      {:error, :no_login} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{code: "no_email", error: "This account has no email address"})

      error ->
        error
    end
  end
end
