defmodule MilosTrainingWeb.PostAttachmentController do
  @moduledoc """
  The card a journal entry or PR makes in a post, before posting (ADR-157):
  after logging a PR the web prefills the compose with it.
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.PostAttachment
  alias MilosTrainingWeb.Schemas.Community
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Community"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:show,
    summary: "Preview the card one of your journal entries or PRs makes in a post",
    parameters: [
      %Parameter{
        name: :type,
        in: :path,
        required: true,
        schema: %Schema{type: :string, enum: MilosTraining.Community.shareable_attachment_types()}
      },
      %Parameter{name: :id, in: :path, required: true, schema: Community.uuid()}
    ],
    responses: [
      ok:
        {"Attachment", "application/json",
         %Schema{
           title: "PostAttachmentPreview",
           type: :object,
           required: [:attachment_type, :attachment_id, :attachment],
           properties: %{
             attachment_type: %Schema{type: :string},
             attachment_id: Community.uuid(),
             attachment: %Schema{type: :object, additionalProperties: true}
           }
         }}
    ]
  )

  def show(conn, %{type: type, id: id}) do
    with {:ok, preview} <- PostAttachment.preview(conn.assigns.user_context.user_id, type, id) do
      json(conn, preview)
    end
  end
end
