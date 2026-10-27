defmodule PaleeWeb.ShareLinkEmailController do
  @moduledoc """
  ADR-210: "Send by email" for a member's share link (guest pass, check-in
  buddy invite link, «Φέρε φίλο»).
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.ShareLinkEmails
  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Share links"])
  security([%{"bearerAuth" => []}])

  operation(:create,
    summary: "Email one of your share links to an address (ADR-210)",
    description:
      "The link is rebuilt from `token` and must be yours and still usable. Needs a verified " <>
        "email; at most 10 a day. The same link to the same address is sent once.",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              link: %Schema{type: :string, enum: ~w(guest_pass buddy_invite referral)},
              token: %Schema{
                type: :string,
                description: "The guest pass or buddy invite token, or the referral code"
              },
              to: %Schema{type: :string, format: :email}
            },
            required: [:link, :token, :to]
          }
        }
      }
    },
    responses: [
      accepted:
        {"Queued", "application/json",
         %Schema{
           type: :object,
           properties: %{
             delivery: %Schema{
               type: :object,
               properties: %{
                 id: %Schema{type: :string, format: :uuid},
                 status: %Schema{type: :string, enum: ~w(queued deferred sent failed suppressed)}
               },
               required: [:id, :status]
             }
           },
           required: [:delivery]
         }}
    ]
  )

  def create(conn, _params) do
    with {:ok, delivery} <-
           ShareLinkEmails.send(conn.assigns.user_context.account, conn.body_params) do
      conn
      |> put_status(:accepted)
      |> json(%{delivery: Map.take(delivery, [:id, :status])})
    end
  end
end
