defmodule PaleeWeb.PasswordRecoveryController.Body do
  @moduledoc false
  alias OpenApiSpex.{RequestBody, Schema}

  def json(properties, required) do
    %RequestBody{
      required: true,
      content: %{
        "application/json" => %OpenApiSpex.MediaType{
          schema: %Schema{type: :object, properties: properties, required: required}
        }
      }
    }
  end
end

defmodule PaleeWeb.PasswordRecoveryController do
  @moduledoc """
  ADR-187: password recovery without a mail service. The person asks for a
  reset, and a handler (vendor, box staff, their coach) claims the request
  and mails them a one-time link; or the person uses a recovery code.
  """
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias OpenApiSpex.Schema
  alias Palee.Application.PasswordRecovery
  alias PaleeWeb.PasswordRecoveryController.Body

  action_fallback PaleeWeb.FallbackController

  tags(["Password recovery"])

  @person_schema %Schema{
    type: :object,
    properties: %{
      user_id: %Schema{type: :string, format: :uuid},
      handle: %Schema{type: :string},
      display_name: %Schema{type: :string},
      avatar_url: %Schema{type: :string, nullable: true},
      email: %Schema{type: :string, nullable: true}
    },
    required: [:user_id, :handle, :display_name]
  }

  @request_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      state: %Schema{type: :string, enum: ["open", "mine", "taken", "link_sent", "expired"]},
      person: @person_schema,
      claimed_by: %Schema{
        type: :object,
        nullable: true,
        properties: %{
          user_id: %Schema{type: :string, format: :uuid},
          handle: %Schema{type: :string},
          display_name: %Schema{type: :string}
        }
      },
      sources: %Schema{type: :array, items: %Schema{type: :string}},
      organizations: %Schema{type: :array, items: %Schema{type: :string}},
      requested_at: %Schema{type: :string, format: :"date-time"},
      link_issued_at: %Schema{type: :string, format: :"date-time", nullable: true},
      link_expires_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:id, :state, :person, :sources, :organizations, :requested_at]
  }

  @request_envelope %Schema{
    type: :object,
    properties: %{request: @request_schema},
    required: [:request]
  }

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [:request, :complete, :redeem_code, :generate_codes]

  operation(:request,
    summary: "Ask for a password reset (always answered the same way)",
    request_body: Body.json(%{identifier: %Schema{type: :string}}, [:identifier]),
    responses: [accepted: {"Request sent", "application/json", %Schema{type: :object}}]
  )

  operation(:complete,
    summary: "Set a new password with a reset link's token",
    request_body:
      Body.json(%{token: %Schema{type: :string}, password: %Schema{type: :string}}, [
        :token,
        :password
      ]),
    responses: [
      no_content: "Password changed",
      unprocessable_entity:
        {"Invalid link or password", "application/json", %Schema{type: :object}},
      gone: {"Expired link", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:redeem_code,
    summary: "Set a new password with a recovery code",
    request_body:
      Body.json(
        %{
          identifier: %Schema{type: :string},
          code: %Schema{type: :string},
          password: %Schema{type: :string}
        },
        [:identifier, :code, :password]
      ),
    responses: [
      no_content: "Password changed",
      unprocessable_entity: {"Wrong account or code", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:codes_status,
    summary: "How many recovery codes the login has left",
    security: [%{"bearerAuth" => []}],
    responses: [
      ok:
        {"Recovery codes", "application/json",
         %Schema{
           type: :object,
           properties: %{total: %Schema{type: :integer}, unused: %Schema{type: :integer}},
           required: [:total, :unused]
         }}
    ]
  )

  operation(:generate_codes,
    summary: "New recovery codes (the old ones stop working)",
    security: [%{"bearerAuth" => []}],
    request_body: Body.json(%{current_password: %Schema{type: :string}}, [:current_password]),
    responses: [
      created:
        {"Recovery codes", "application/json",
         %Schema{
           type: :object,
           properties: %{codes: %Schema{type: :array, items: %Schema{type: :string}}},
           required: [:codes]
         }},
      unprocessable_entity: {"Wrong password", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:inbox,
    summary: "The password reset requests the signed-in person can handle",
    security: [%{"bearerAuth" => []}],
    responses: [
      ok:
        {"Requests", "application/json",
         %Schema{
           type: :object,
           properties: %{requests: %Schema{type: :array, items: @request_schema}},
           required: [:requests]
         }}
    ]
  )

  operation(:claim,
    summary: "Open a request and claim it",
    security: [%{"bearerAuth" => []}],
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Request", "application/json", @request_envelope},
      conflict: {"Someone else holds it", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:release,
    summary: "Let go of a claimed request",
    security: [%{"bearerAuth" => []}],
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok: {"Request", "application/json", @request_envelope},
      conflict: {"Not yours", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:issue_link,
    summary: "Issue the one-time reset link (24 hours) to mail to the person",
    security: [%{"bearerAuth" => []}],
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [
      ok:
        {"Reset link", "application/json",
         %Schema{
           type: :object,
           properties: %{
             token: %Schema{type: :string},
             email: %Schema{type: :string},
             expires_at: %Schema{type: :string, format: :"date-time"},
             request: @request_schema
           },
           required: [:token, :email, :expires_at, :request]
         }},
      conflict: {"Someone else holds it", "application/json", %Schema{type: :object}}
    ]
  )

  operation(:reject,
    summary: "Close a request that could not be confirmed",
    security: [%{"bearerAuth" => []}],
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [no_content: "Done"]
  )

  operation(:dismiss,
    summary: "Clear an expired request",
    security: [%{"bearerAuth" => []}],
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [no_content: "Done"]
  )

  operation(:hide,
    summary: "Hide a request from your own list",
    security: [%{"bearerAuth" => []}],
    parameters: [id: [in: :path, type: :string, required: true]],
    responses: [no_content: "Done"]
  )

  operation(:log,
    summary: "The password reset security log (vendor only)",
    security: [%{"bearerAuth" => []}],
    responses: [
      ok:
        {"Log", "application/json",
         %Schema{
           type: :object,
           properties: %{
             entries: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   id: %Schema{type: :string, format: :uuid},
                   event: %Schema{type: :string},
                   handle: %Schema{type: :string, nullable: true},
                   handler_handle: %Schema{type: :string, nullable: true},
                   inserted_at: %Schema{type: :string, format: :"date-time"}
                 },
                 required: [:id, :event, :inserted_at]
               }
             }
           },
           required: [:entries]
         }}
    ]
  )

  def request(conn, _params) do
    :ok = PasswordRecovery.request(conn.body_params.identifier)

    conn
    |> put_status(:accepted)
    |> json(%{status: "sent"})
  end

  def complete(conn, _params) do
    with :ok <- PasswordRecovery.complete(conn.body_params.token, conn.body_params.password) do
      send_resp(conn, :no_content, "")
    end
  end

  def redeem_code(conn, _params) do
    %{identifier: identifier, code: code, password: password} = conn.body_params

    with :ok <- PasswordRecovery.redeem_code(identifier, code, password) do
      send_resp(conn, :no_content, "")
    end
  end

  def codes_status(conn, _params) do
    json(conn, PasswordRecovery.codes_status(GuardianPlug.current_resource(conn)))
  end

  def generate_codes(conn, _params) do
    with {:ok, codes} <-
           PasswordRecovery.generate_codes(
             GuardianPlug.current_resource(conn),
             conn.body_params.current_password
           ) do
      conn
      |> put_status(:created)
      |> json(%{codes: codes})
    end
  end

  def inbox(conn, _params) do
    json(conn, %{requests: PasswordRecovery.inbox(GuardianPlug.current_resource(conn))})
  end

  def claim(conn, %{"id" => id}),
    do: respond(conn, PasswordRecovery.claim(GuardianPlug.current_resource(conn), id))

  def release(conn, %{"id" => id}),
    do: respond(conn, PasswordRecovery.release(GuardianPlug.current_resource(conn), id))

  def issue_link(conn, %{"id" => id}) do
    with {:ok, link} <- PasswordRecovery.issue_link(GuardianPlug.current_resource(conn), id) do
      json(conn, link)
    end
  end

  def reject(conn, %{"id" => id}), do: close(conn, id, :rejected)
  def dismiss(conn, %{"id" => id}), do: close(conn, id, :dismissed)

  def hide(conn, %{"id" => id}) do
    with :ok <- PasswordRecovery.hide(GuardianPlug.current_resource(conn), id) do
      send_resp(conn, :no_content, "")
    end
  end

  def log(conn, _params), do: json(conn, %{entries: PasswordRecovery.log_entries()})

  defp close(conn, id, outcome) do
    with :ok <- PasswordRecovery.close(GuardianPlug.current_resource(conn), id, outcome) do
      send_resp(conn, :no_content, "")
    end
  end

  defp respond(conn, {:ok, request}), do: json(conn, %{request: request})
  defp respond(_conn, error), do: error
end
