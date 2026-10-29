defmodule PaleeWeb.AdminDeskBuyersController do
  @moduledoc """
  Staff › «Είσπραξη» on the phone (ADR-272): who pays («Ποιος;»), what they
  can pay («Τι;»), and making a found person or a walk-in a guest of the
  box so they can buy a πακέτο συνδρομής at the desk.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Payments.DeskBuyers
  alias PaleeWeb.Schemas.Payments, as: P
  alias PaleeWeb.Schemas.TerminalPayments, as: T

  action_fallback PaleeWeb.FallbackController

  tags(["Payments"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:people,
    summary: "Who can pay at the desk",
    description:
      "Without `q`, the people who checked in today; with it, the box's members, athletes " <>
        "and guests whose name or email matches, or a Palee account outside the box when `q` " <>
        "is its exact email.",
    parameters: [
      %Parameter{
        name: :q,
        in: :query,
        required: false,
        schema: %Schema{type: :string, maxLength: 120}
      }
    ],
    responses: [ok: {"People", "application/json", T.desk_people()}]
  )

  def people(conn, params) do
    with {:ok, payload} <- DeskBuyers.people(conn.assigns.tenant_context, params) do
      json(conn, payload)
    end
  end

  operation(:options,
    summary: "What a person (or a walk-in, without `user_id`) can pay at the desk",
    parameters: [
      %Parameter{name: :user_id, in: :query, required: false, schema: P.uuid()}
    ],
    responses: [ok: {"Options", "application/json", T.desk_options()}]
  )

  def options(conn, params) do
    with {:ok, options} <-
           DeskBuyers.options(conn.assigns.tenant_context, Map.get(params, :user_id)) do
      json(conn, %{options: options})
    end
  end

  operation(:make_guest,
    summary: "Make a found person, or a walk-in who signs up, a guest of the box",
    description:
      "`user_id` for a person found by «Ποιος;», or `name` and `email` for a walk-in (a new " <>
        "held profile, ADR-254, or the account that already has that email). Someone who is " <>
        "already a box member, athlete or guest stays as they are (`added: false`).",
    request_body: P.body(T.guest_body()),
    responses: [
      created: {"Guest", "application/json", T.guest()},
      ok: {"Already buying here", "application/json", T.guest()}
    ]
  )

  def make_guest(conn, _params) do
    with {:ok, guest} <- DeskBuyers.make_guest(conn.assigns.tenant_context, conn.body_params) do
      conn
      |> put_status(if(guest.added, do: :created, else: :ok))
      |> json(guest)
    end
  end
end
