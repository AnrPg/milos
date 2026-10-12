defmodule MilosTrainingWeb.OwnerOrganizationController do
  @moduledoc "What only a gym's owner does: new gym, hand over, archive (ADR-099)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Organizations
  alias Guardian.Plug, as: GuardianPlug
  alias MilosTrainingWeb.Schemas.OwnerOrganization, as: S
  alias OpenApiSpex.Schema

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Organization ownership"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:create,
    summary: "An owner creates another gym and owns it",
    request_body: S.body(%{name: %Schema{type: :string}}, [:name]),
    responses: [created: {"Gym", "application/json", S.organization()}]
  )

  def create(conn, _params) do
    account = GuardianPlug.current_resource(conn)

    with {:ok, organization} <-
           Organizations.create_owned_organization(account, %{name: conn.body_params.name}) do
      conn |> put_status(:created) |> json(serialize(organization))
    end
  end

  operation(:transfer,
    summary: "Hand ownership to an active member; the former owner stays as admin",
    request_body: S.body(%{user_id: %Schema{type: :string, format: :uuid}}, [:user_id]),
    responses: [ok: {"Gym", "application/json", S.organization()}]
  )

  def transfer(conn, _params) do
    context = conn.assigns.tenant_context

    with {:ok, _membership} <-
           Organizations.transfer_ownership(context, conn.body_params.user_id) do
      json(conn, serialize(context.organization))
    end
  end

  operation(:archive,
    summary: "Archive the gym; access closes for everyone (confirm with its slug)",
    request_body: S.body(%{confirm: %Schema{type: :string}}, [:confirm]),
    responses: [ok: {"Gym", "application/json", S.organization()}]
  )

  def archive(conn, _params) do
    with {:ok, organization} <-
           Organizations.archive_organization(
             conn.assigns.tenant_context,
             conn.body_params.confirm
           ) do
      json(conn, serialize(organization))
    end
  end

  defp serialize(organization),
    do: Map.take(organization, [:id, :slug, :name, :status])
end
