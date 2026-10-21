defmodule PaleeWeb.AdminTrialController do
  @moduledoc "Staff run the box's trials: the rules and the queue (ADR-144, board 6 Q3–Q4)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.Trials
  alias PaleeWeb.Schemas.Trials, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Trials"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @refused [
    not_found: {"No such trial", "application/json", %Schema{type: :object}},
    unprocessable_entity:
      {"The trial can't take this step", "application/json", %Schema{type: :object}}
  ]

  operation(:policy,
    summary: "The box's trial rules and this week's trial count",
    responses: [ok: {"Policy", "application/json", S.policy_response()}]
  )

  def policy(conn, _params), do: json(conn, Trials.policy(conn.assigns.tenant_context))

  operation(:update_policy,
    summary: "Change the box's trial rules",
    request_body: S.body(S.policy()),
    responses: [
      ok: {"Policy", "application/json", S.policy_response()},
      unprocessable_entity: {"Invalid rules", "application/json", %Schema{type: :object}}
    ]
  )

  def update_policy(conn, _params) do
    with {:ok, policy} <- Trials.update_policy(conn.assigns.tenant_context, conn.body_params),
         do: json(conn, policy)
  end

  operation(:queue,
    summary: "Trials in one stage of the funnel, with the count per stage and the last 30 days",
    parameters: [
      %Parameter{name: :stage, in: :query, required: false, schema: S.stage()}
    ],
    responses: [ok: {"Queue", "application/json", S.queue_response()}]
  )

  def queue(conn, params),
    do: json(conn, Trials.queue(conn.assigns.tenant_context, Map.get(params, :stage, "requests")))

  operation(:accept,
    summary: "Accept a trial request: the seat is booked",
    parameters: [@id],
    responses: [ok: {"Trial", "application/json", S.staff_trial_response()}] ++ @refused
  )

  def accept(conn, %{id: id}) do
    with {:ok, trial} <- Trials.accept(conn.assigns.tenant_context, id, actor(conn)),
         do: json(conn, %{trial: trial})
  end

  operation(:decline,
    summary: "Decline a trial request, with an optional reason the person sees",
    parameters: [@id],
    request_body: S.body(S.decline_request()),
    responses: [ok: {"Trial", "application/json", S.staff_trial_response()}] ++ @refused
  )

  def decline(conn, %{id: id}) do
    reason = Map.get(conn.body_params, :reason)

    with {:ok, trial} <- Trials.decline(conn.assigns.tenant_context, id, actor(conn), reason),
         do: json(conn, %{trial: trial})
  end

  operation(:attendance,
    summary: "Ήρθε / Δεν ήρθε (recorded on the class roster)",
    parameters: [@id],
    request_body: S.body(S.attendance_request()),
    responses: [ok: {"Trial", "application/json", S.staff_trial_response()}] ++ @refused
  )

  def attendance(conn, %{id: id}) do
    with {:ok, trial} <-
           Trials.record_attendance(
             conn.assigns.tenant_context,
             id,
             actor(conn),
             conn.body_params.status
           ),
         do: json(conn, %{trial: trial})
  end

  defp actor(conn), do: %{id: conn.assigns.tenant_context.user_id}
end
