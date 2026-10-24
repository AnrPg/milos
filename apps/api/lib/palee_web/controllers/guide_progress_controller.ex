defmodule PaleeWeb.GuideProgressController do
  @moduledoc "A person's progress through the in-app walkthroughs (ADR-193)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{MediaType, Parameter, RequestBody}
  alias Palee.Application.GuideProgress
  alias PaleeWeb.Schemas.Guides, as: Schemas

  action_fallback PaleeWeb.FallbackController

  tags(["Me"])
  security([%{"bearerAuth" => []}])

  @guide %Parameter{name: :guide_id, in: :path, required: true, schema: Schemas.guide_id()}

  operation(:index,
    summary: "Your progress in every walkthrough you have opened",
    responses: [ok: {"Guide progress", "application/json", Schemas.progress_list()}]
  )

  def index(conn, _params) do
    with {:ok, body} <- GuideProgress.list(conn.assigns.user_context), do: json(conn, body)
  end

  operation(:update,
    summary: "Record a step reached, a finish or a «not now» in one walkthrough",
    parameters: [@guide],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: Schemas.update_request()}}
    },
    responses: [ok: {"Guide progress", "application/json", Schemas.progress()}]
  )

  def update(conn, %{"guide_id" => guide_id}) do
    with {:ok, progress} <-
           GuideProgress.put(conn.assigns.user_context, guide_id, conn.body_params) do
      json(conn, progress)
    end
  end

  operation(:delete,
    summary: "Forget one walkthrough's progress, so it is offered again",
    parameters: [@guide],
    responses: [ok: {"Guide progress", "application/json", Schemas.progress_list()}]
  )

  def delete(conn, %{"guide_id" => guide_id}) do
    with {:ok, body} <- GuideProgress.reset(conn.assigns.user_context, guide_id),
         do: json(conn, body)
  end
end
