defmodule PaleeWeb.BusinessAccountController do
  @moduledoc """
  ADR-184, for the signed-in person: the business step of sign-up, their
  requests to the platform team (Εγώ › Ρυθμίσεις) and the activation link.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.{AbandonedDemos, BusinessActivation, BusinessRequests, BusinessSignUp}
  alias PaleeWeb.BusinessAccountJSON
  alias PaleeWeb.Schemas.BusinessAccounts, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Business accounts"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:sign_up,
    summary: "Open a gym or independent-coach business in demo mode (sign-up only)",
    description:
      "Within 30 minutes of registering. Older accounts file a conversion request " <>
        "(`business_signup_closed`).",
    request_body: S.sign_up_body(),
    responses: [created: {"Business", "application/json", S.business_organization()}]
  )

  def sign_up(conn, _params) do
    with {:ok, organization} <- BusinessSignUp.call(account(conn), conn.body_params) do
      conn |> put_status(:created) |> json(BusinessAccountJSON.organization(organization))
    end
  end

  operation(:my_requests,
    summary: "The person's requests to the platform team",
    responses: [ok: {"Requests", "application/json", S.requests()}]
  )

  def my_requests(conn, _params) do
    with {:ok, requests} <- BusinessRequests.mine(account(conn)) do
      json(conn, %{requests: Enum.map(requests, &BusinessAccountJSON.request/1)})
    end
  end

  operation(:request_conversion,
    summary: "Ask the platform team to turn this account into a business",
    request_body: S.conversion_body(),
    responses: [created: {"Request", "application/json", S.request()}]
  )

  def request_conversion(conn, _params) do
    with {:ok, request} <- BusinessRequests.request_conversion(account(conn), conn.body_params) do
      conn |> put_status(:created) |> json(BusinessAccountJSON.request(request))
    end
  end

  operation(:cancel_request,
    summary: "Withdraw a pending request",
    parameters: [@id],
    responses: [ok: {"Request", "application/json", S.request()}]
  )

  def cancel_request(conn, %{id: id}) do
    with {:ok, request} <- BusinessRequests.cancel(account(conn), id) do
      json(conn, BusinessAccountJSON.request(request))
    end
  end

  operation(:archived_demos,
    summary: "The person's demo businesses archived for inactivity",
    responses: [ok: {"Archived demos", "application/json", S.archived_demos()}]
  )

  def archived_demos(conn, _params) do
    with {:ok, demos} <- AbandonedDemos.list_archived(account(conn)) do
      json(conn, %{businesses: Enum.map(demos, &BusinessAccountJSON.archived_demo/1)})
    end
  end

  operation(:reopen_demo,
    summary: "Reopen an archived demo business: empty, in demo mode, activation requested",
    parameters: [@id],
    responses: [ok: {"Reopened", "application/json", S.reopened_demo()}]
  )

  def reopen_demo(conn, %{id: id}) do
    with {:ok, %{organization: organization, request: request}} <-
           AbandonedDemos.reopen(account(conn), id) do
      json(conn, %{
        organization: BusinessAccountJSON.organization(organization),
        request: BusinessAccountJSON.request(request)
      })
    end
  end

  operation(:inspect_activation,
    summary: "What an activation link would activate (the account it names only)",
    request_body: S.token_body(),
    responses: [ok: {"Preview", "application/json", S.activation_preview()}]
  )

  def inspect_activation(conn, _params) do
    with {:ok, preview} <- BusinessActivation.inspect(account(conn), conn.body_params.token) do
      json(conn, BusinessAccountJSON.preview(preview))
    end
  end

  operation(:redeem_activation,
    summary: "Activate the business: demo data removed, gates lifted",
    request_body: S.token_body(),
    responses: [ok: {"Activated", "application/json", S.activation_result()}]
  )

  def redeem_activation(conn, _params) do
    with {:ok, result} <- BusinessActivation.redeem(account(conn), conn.body_params.token) do
      json(conn, BusinessAccountJSON.activation(result))
    end
  end

  defp account(conn), do: GuardianPlug.current_resource(conn)
end
