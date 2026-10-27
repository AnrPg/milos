defmodule PaleeWeb.SecurityLinkController do
  @moduledoc "ADR-208: the links of security notices that need no session."
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{RequestBody, Schema}
  alias Palee.Application.SignOutEverywhereLink

  @error_schema %Schema{
    type: :object,
    properties: %{
      code: %Schema{type: :string, enum: ["invalid_link", "expired_link", "used_link"]},
      error: %Schema{type: :string}
    },
    required: [:code, :error]
  }

  tags(["Authentication"])

  operation(:sign_out_everywhere,
    summary: "Sign every device of the login out with a security notice's emailed link",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %OpenApiSpex.MediaType{
          schema: %Schema{
            type: :object,
            properties: %{token: %Schema{type: :string}},
            required: [:token]
          }
        }
      }
    },
    responses: [
      no_content: {"Every session ended", nil, nil},
      unprocessable_entity: {"Unknown link", "application/json", @error_schema},
      gone: {"Expired or already used link", "application/json", @error_schema}
    ]
  )

  def sign_out_everywhere(conn, _params) do
    token = Map.get(conn.body_params, "token") || Map.get(conn.body_params, :token)

    case SignOutEverywhereLink.call(token) do
      :ok ->
        conn
        |> delete_resp_cookie("palee_refresh", path: "/api/auth")
        |> send_resp(:no_content, "")

      {:error, :expired} ->
        error(conn, :gone, "expired_link", "This link has expired")

      {:error, :used} ->
        error(conn, :gone, "used_link", "This link was already used")

      {:error, _invalid} ->
        error(conn, :unprocessable_entity, "invalid_link", "This link is not valid")
    end
  end

  defp error(conn, status, code, message),
    do: conn |> put_status(status) |> json(%{code: code, error: message})
end
