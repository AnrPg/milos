defmodule MilosTrainingWeb.AdminWorkoutFolderController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}
  alias MilosTraining.Workouts

  action_fallback MilosTrainingWeb.FallbackController
  tags(["Admin Workouts"])
  security([%{"bearerAuth" => []}])

  @folder %Schema{
    type: :object,
    additionalProperties: false,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      name: %Schema{type: :string},
      parent_id: %Schema{type: :string, format: :uuid, nullable: true},
      created_by_id: %Schema{type: :string, format: :uuid}
    },
    required: [:id, :name, :created_by_id]
  }
  @body %RequestBody{
    required: true,
    content: %{
      "application/json" => %MediaType{
        schema: %Schema{
          type: :object,
          additionalProperties: false,
          properties: %{
            name: %Schema{type: :string, minLength: 1, maxLength: 120},
            parent_id: %Schema{type: :string, format: :uuid, nullable: true}
          },
          required: [:name]
        }
      }
    }
  }
  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:index,
    summary: "List nested workout-library folders",
    responses: [
      ok:
        {"Folders", "application/json",
         %Schema{
           type: :object,
           properties: %{folders: %Schema{type: :array, items: @folder}},
           required: [:folders]
         }}
    ]
  )

  operation(:create,
    summary: "Create a workout-library folder",
    request_body: @body,
    responses: [created: {"Folder", "application/json", @folder}]
  )

  operation(:update,
    summary: "Rename or reparent a workout-library folder",
    parameters: [@id],
    request_body: @body,
    responses: [ok: {"Folder", "application/json", @folder}]
  )

  operation(:delete,
    summary: "Delete a folder and move its contents to its parent",
    parameters: [@id],
    responses: [no_content: "Deleted"]
  )

  def index(conn, _params),
    do: json(conn, %{folders: Workouts.list_folders(conn.assigns.tenant_context)})

  def create(conn, _params) do
    admin = Guardian.Plug.current_resource(conn)

    with {:ok, folder} <-
           Workouts.create_folder(conn.assigns.tenant_context, admin.id, conn.body_params) do
      conn |> put_status(:created) |> json(folder)
    end
  end

  def update(conn, params) do
    with {:ok, folder} <-
           Workouts.update_folder(
             conn.assigns.tenant_context,
             params["id"] || params[:id],
             conn.body_params
           ) do
      json(conn, folder)
    end
  end

  def delete(conn, params) do
    with :ok <- Workouts.delete_folder(conn.assigns.tenant_context, params["id"] || params[:id]) do
      send_resp(conn, :no_content, "")
    end
  end
end
