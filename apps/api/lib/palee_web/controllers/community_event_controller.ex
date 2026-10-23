defmodule PaleeWeb.CommunityEventController do
  @moduledoc """
  Club events from your personal session (ADR-153): lists, the event page,
  «Θα έρθω», guest pass links, a box page's open events, and running events
  from the club page for whoever holds `manage_events` at its box.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{CommunityEvents, EventHosts}
  alias PaleeWeb.Schemas.CommunityEvents, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Community events"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @slug %Parameter{
    name: :slug,
    in: :path,
    required: true,
    description: "The box's slug or one of its former slugs",
    schema: %Schema{type: :string, maxLength: 120}
  }
  @scope %Parameter{
    name: :scope,
    in: :query,
    required: false,
    schema: %Schema{type: :string, enum: ~w(upcoming past)}
  }
  @invite %Parameter{
    name: :invite,
    in: :query,
    required: false,
    description: "The token of a guest pass link",
    schema: %Schema{type: :string, maxLength: 2000}
  }
  @events {"Events", "application/json", S.events_response()}
  @event {"Event", "application/json", S.event_response()}

  operation(:club_events,
    summary: "A club's events: upcoming (cancelled ones flagged) or past",
    parameters: [@id, @scope],
    responses: [ok: @events]
  )

  def club_events(conn, %{id: id} = params) do
    with {:ok, result} <- CommunityEvents.club_events(conn.assigns.user_context, id, params),
         do: json(conn, result)
  end

  operation(:create,
    summary: "Create an event in a club (staff and coaches); weekly with repeat_until",
    parameters: [@id],
    request_body: S.body(S.create_request()),
    responses: [created: {"Created", "application/json", S.created_response()}]
  )

  def create(conn, %{id: id}) do
    with {:ok, result} <- CommunityEvents.create(conn.assigns.user_context, id, conn.body_params) do
      conn |> put_status(:created) |> json(result)
    end
  end

  operation(:clubs_events,
    summary: "Upcoming events across every club you can see",
    responses: [ok: @events]
  )

  def clubs_events(conn, _params) do
    with {:ok, result} <- CommunityEvents.clubs_events(conn.assigns.user_context),
         do: json(conn, result)
  end

  operation(:mine,
    summary: "Your upcoming events at any box: going or on the waitlist",
    responses: [ok: @events]
  )

  def mine(conn, _params) do
    with {:ok, result} <- CommunityEvents.my_events(conn.assigns.user_context),
         do: json(conn, result)
  end

  operation(:box_events,
    summary: "A published box's upcoming events open to everyone (its page's Events tab)",
    parameters: [@slug],
    responses: [ok: @events]
  )

  def box_events(conn, %{slug: slug}) do
    with {:ok, result} <- CommunityEvents.box_events(conn.assigns.user_context, slug),
         do: json(conn, result)
  end

  operation(:show,
    summary: "An event; with ?invite= it also says who invited you and if a place is left",
    parameters: [@id, @invite],
    responses: [ok: @event]
  )

  def show(conn, %{id: id} = params) do
    reply(conn, CommunityEvents.show(conn.assigns.user_context, id, params[:invite]))
  end

  operation(:update,
    summary: "Edit an event (staff and coaches): this one or this and following",
    parameters: [@id],
    request_body: S.body(S.update_request()),
    responses: [ok: @event]
  )

  def update(conn, %{id: id}),
    do: reply(conn, CommunityEvents.update(conn.assigns.user_context, id, conn.body_params))

  operation(:cancel,
    summary: "Cancel an event (staff and coaches): this one or this and following",
    parameters: [@id],
    request_body: S.body(S.cancel_request()),
    responses: [ok: @event]
  )

  def cancel(conn, %{id: id}),
    do: reply(conn, CommunityEvents.cancel(conn.assigns.user_context, id, conn.body_params))

  operation(:rsvp,
    summary: "«Θα έρθω» (a place, or the waitlist when full) or «Δεν θα έρθω»",
    parameters: [@id],
    request_body: S.body(S.rsvp_request()),
    responses: [ok: @event]
  )

  def rsvp(conn, %{id: id}),
    do: reply(conn, CommunityEvents.rsvp(conn.assigns.user_context, id, conn.body_params))

  operation(:invite,
    summary: "Your guest pass link for an event you are going to",
    parameters: [@id],
    responses: [created: {"Invitation", "application/json", S.invite_response()}]
  )

  def invite(conn, %{id: id}) do
    with {:ok, invitation} <- CommunityEvents.invite(conn.assigns.user_context, id) do
      conn |> put_status(:created) |> json(invitation)
    end
  end

  # ADR-185: «Διοργάνωση ως».
  operation(:hosts,
    summary: "Who you can host an event as: «Ως εγώ» and each business where you run events",
    responses: [ok: {"Hosts", "application/json", S.hosts_response()}]
  )

  def hosts(conn, _params) do
    with {:ok, result} <- EventHosts.hosts(conn.assigns.user_context),
         do: json(conn, result)
  end

  operation(:host_create,
    summary:
      "Create an event as yourself (open to everyone or by invitation) or as a business; rate limited",
    request_body: S.body(S.host_create_request()),
    responses: [created: {"Created", "application/json", S.created_response()}]
  )

  def host_create(conn, _params) do
    with {:ok, result} <- EventHosts.create(conn.assigns.user_context, conn.body_params) do
      conn |> put_status(:created) |> json(result)
    end
  end

  operation(:view,
    summary:
      "Counts an open of the event page (once per person and day, without keeping who; hosts are not counted)",
    parameters: [@id],
    responses: [ok: {"View", "application/json", S.view_response()}]
  )

  def view(conn, %{id: id}) do
    with {:ok, result} <- CommunityEvents.record_view(conn.assigns.user_context, id),
         do: json(conn, result)
  end

  defp reply(conn, {:ok, event}), do: json(conn, %{event: event})
  defp reply(_conn, error), do: error
end
