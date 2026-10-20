defmodule MilosTrainingWeb.AdminCommunityEventController do
  @moduledoc """
  «Κοινότητα › Events» for staff (ADR-153, board 8): the box's events, their
  attendees and numbers, «Ήρθε», «Πλήρωσε», freeing a place, «Μήνυμα σε
  όλους» and the trial offer after the event.
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.StaffCommunityEvents
  alias MilosTrainingWeb.Schemas.CommunityEvents, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Admin Community"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @uuid %Schema{type: :string, format: :uuid}
  @id %Parameter{name: :id, in: :path, required: true, schema: @uuid}
  @user_id %Parameter{name: :user_id, in: :path, required: true, schema: @uuid}
  @scope %Parameter{
    name: :scope,
    in: :query,
    required: false,
    schema: %Schema{type: :string, enum: ~w(upcoming past)}
  }
  @event {"Event", "application/json", S.staff_event_response()}

  operation(:index,
    summary: "The box's upcoming (default) or past events, with their numbers",
    parameters: [@scope],
    responses: [ok: {"Events", "application/json", S.staff_events_response()}]
  )

  def index(conn, params) do
    with {:ok, result} <- StaffCommunityEvents.list(conn.assigns.tenant_context, params),
         do: json(conn, result)
  end

  operation(:create,
    summary: "Create an event in one of the box's clubs; weekly with repeat_until",
    request_body: S.body(S.create_request(true)),
    responses: [created: {"Created", "application/json", S.staff_created_response()}]
  )

  def create(conn, _params) do
    with {:ok, result} <-
           StaffCommunityEvents.create(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(result)
    end
  end

  operation(:show,
    summary: "An event with its attendees, numbers and trial offer",
    parameters: [@id],
    responses: [ok: @event]
  )

  def show(conn, %{id: id}),
    do: reply(conn, StaffCommunityEvents.show(conn.assigns.tenant_context, id))

  operation(:update,
    summary: "Edit an event: this one or this and following",
    parameters: [@id],
    request_body: S.body(S.update_request()),
    responses: [ok: @event]
  )

  def update(conn, %{id: id}),
    do:
      reply(conn, StaffCommunityEvents.update(conn.assigns.tenant_context, id, conn.body_params))

  operation(:cancel,
    summary: "Cancel an event: this one or this and following; people going hear why",
    parameters: [@id],
    request_body: S.body(S.cancel_request()),
    responses: [ok: @event]
  )

  def cancel(conn, %{id: id}),
    do:
      reply(conn, StaffCommunityEvents.cancel(conn.assigns.tenant_context, id, conn.body_params))

  operation(:check_in,
    summary: "«Ήρθε» for someone holding a place, or undo it",
    parameters: [@id, @user_id],
    request_body: S.body(S.check_in_request()),
    responses: [ok: @event]
  )

  def check_in(conn, %{id: id, user_id: user_id}) do
    reply(
      conn,
      StaffCommunityEvents.check_in(
        conn.assigns.tenant_context,
        id,
        user_id,
        conn.body_params.checked_in
      )
    )
  end

  operation(:mark_paid,
    summary: "«Πλήρωσε»: record a payment at the box (a Finance receipt when possible)",
    parameters: [@id, @user_id],
    request_body: S.body(S.paid_request()),
    responses: [ok: @event]
  )

  def mark_paid(conn, %{id: id, user_id: user_id}) do
    reply(
      conn,
      StaffCommunityEvents.mark_paid(
        conn.assigns.tenant_context,
        id,
        user_id,
        conn.body_params.payment_method
      )
    )
  end

  operation(:remove,
    summary: "Free someone's place; the first on the waitlist moves up",
    parameters: [@id, @user_id],
    responses: [ok: @event]
  )

  def remove(conn, %{id: id, user_id: user_id}),
    do: reply(conn, StaffCommunityEvents.remove(conn.assigns.tenant_context, id, user_id))

  operation(:message,
    summary: "«Μήνυμα σε όλους»: a notification to everyone going",
    parameters: [@id],
    request_body: S.body(S.message_request()),
    responses: [ok: {"Sent", "application/json", S.sent_response()}]
  )

  def message(conn, %{id: id}) do
    with {:ok, result} <-
           StaffCommunityEvents.message(conn.assigns.tenant_context, id, conn.body_params.body),
         do: json(conn, result)
  end

  operation(:trial_offer,
    summary: "Send the one trial offer to people who came and are not members",
    parameters: [@id],
    responses: [ok: {"Sent", "application/json", S.sent_response()}]
  )

  def trial_offer(conn, %{id: id}) do
    with {:ok, result} <- StaffCommunityEvents.trial_offer(conn.assigns.tenant_context, id),
         do: json(conn, result)
  end

  defp reply(conn, {:ok, event}), do: json(conn, %{event: event})
  defp reply(_conn, error), do: error
end
