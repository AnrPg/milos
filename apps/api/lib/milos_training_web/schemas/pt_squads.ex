defmodule MilosTrainingWeb.Schemas.PtSquads do
  @moduledoc "OpenAPI schemas for PT squads (ADR-168)."

  alias MilosTrainingWeb.Schemas.Community
  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}
  @datetime %Schema{type: :string, format: :"date-time"}
  @nullable_datetime %Schema{type: :string, format: :"date-time", nullable: true}

  defdelegate body(schema), to: Community

  defp object(title, properties, required),
    do: %Schema{title: title, type: :object, properties: properties, required: required}

  defp list(schema), do: %Schema{type: :array, items: schema}
  defp string(opts \\ []), do: struct(Schema, Keyword.merge([type: :string], opts))

  def squad do
    object(
      "PtSquad",
      %{
        id: @uuid,
        club_id: @uuid,
        name: string(),
        description: string(nullable: true),
        coach: Community.author(),
        member_count: %Schema{type: :integer, description: "Members besides the coach"},
        invite_count: %Schema{
          type: :integer,
          description: "Invitations nobody answered yet (the coach's view; 0 for others)"
        },
        archived_at: @nullable_datetime,
        role: string(enum: ~w(coach member invited)),
        can_manage: %Schema{type: :boolean},
        members: list(squad_member())
      },
      [
        :id,
        :club_id,
        :name,
        :coach,
        :member_count,
        :invite_count,
        :role,
        :can_manage
      ]
    )
  end

  def squad_member do
    object(
      "PtSquadMember",
      %{
        person: Community.author(),
        status: string(enum: ~w(member invited)),
        since: @datetime
      },
      [:person, :status, :since]
    )
  end

  def overview_response do
    object(
      "PtSquadsOverview",
      %{
        organization_id: @uuid,
        can_create: %Schema{type: :boolean, description: "Whether you coach here"},
        limits:
          object(
            "PtSquadLimits",
            %{max_members: %Schema{type: :integer}, max_live_squads: %Schema{type: :integer}},
            [:max_members, :max_live_squads]
          ),
        coached: list(squad()),
        archived: list(squad()),
        joined: list(squad()),
        invites: list(squad()),
        clients: list(Community.author())
      },
      [:organization_id, :can_create, :limits, :coached, :archived, :joined, :invites, :clients]
    )
  end

  def squad_response, do: object("PtSquadResponse", %{squad: squad()}, [:squad])

  def create_request do
    object(
      "PtSquadCreateRequest",
      %{
        name: string(minLength: 2, maxLength: 60),
        description: string(nullable: true, maxLength: 200),
        client_ids: list(@uuid)
      },
      [:name]
    )
  end

  def update_request do
    object(
      "PtSquadUpdateRequest",
      %{
        name: string(minLength: 2, maxLength: 60),
        description: string(nullable: true, maxLength: 200)
      },
      []
    )
  end

  def invite_request,
    do: object("PtSquadInviteRequest", %{user_ids: list(@uuid)}, [:user_ids])

  def answer_request,
    do: object("PtSquadAnswerRequest", %{accept: %Schema{type: :boolean}}, [:accept])

  def outcome_response do
    object(
      "PtSquadOutcome",
      %{squad_id: @uuid, outcome: string(enum: ~w(declined left archived))},
      [:squad_id, :outcome]
    )
  end
end
