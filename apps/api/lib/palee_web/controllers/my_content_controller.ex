defmodule PaleeWeb.MyContentController do
  @moduledoc "Client-facing Phase C content: on-demand video and progress statistics (ADR-098)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias Palee.Application.{GetMyProgress, ListOnDemandVideos}
  alias PaleeWeb.Schemas.Content, as: ContentSchemas
  alias OpenApiSpex.Schema

  action_fallback PaleeWeb.FallbackController

  tags(["Me"])
  security([%{"bearerAuth" => []}])

  @denied {"Not included in the package", "application/json",
           %Schema{type: :object, additionalProperties: true}}

  operation(:videos,
    summary: "On-demand videos included in my package",
    responses: [
      ok:
        {"Videos", "application/json",
         %Schema{
           type: :object,
           properties: %{videos: %Schema{type: :array, items: ContentSchemas.video_schema()}},
           required: [:videos]
         }},
      forbidden: @denied
    ]
  )

  def videos(conn, _params) do
    actor = GuardianPlug.current_resource(conn)

    with {:ok, videos} <- ListOnDemandVideos.call(conn.assigns.tenant_context, actor) do
      json(conn, %{videos: videos})
    end
  end

  operation(:progress,
    summary: "Advanced statistics of my training in this gym",
    responses: [
      ok:
        {"Progress", "application/json",
         %Schema{
           type: :object,
           properties: %{progress: ContentSchemas.progress_schema()},
           required: [:progress]
         }},
      forbidden: @denied
    ]
  )

  def progress(conn, _params) do
    actor = GuardianPlug.current_resource(conn)

    with {:ok, progress} <- GetMyProgress.call(conn.assigns.tenant_context, actor) do
      json(conn, %{progress: progress})
    end
  end
end
