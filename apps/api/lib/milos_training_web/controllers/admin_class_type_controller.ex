defmodule MilosTrainingWeb.AdminClassTypeController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    ArchiveClassType,
    CreateClassType,
    ListClassTypes,
    UpdateClassType
  }

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Admin Class Types"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true] when action in [:create, :update, :delete]

  @class_type_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      name: %Schema{type: :string},
      slug: %Schema{type: :string},
      sort_order: %Schema{type: :integer},
      archived_at: %Schema{type: :string, format: :"date-time", nullable: true},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"},
      future_classes_reassigned: %Schema{type: :integer}
    },
    required: [:id, :name, :slug, :sort_order, :archived_at]
  }

  @write_schema %Schema{
    type: :object,
    properties: %{
      name: %Schema{type: :string, minLength: 2, maxLength: 80},
      sort_order: %Schema{type: :integer, minimum: 0, default: 0}
    },
    required: [:name]
  }

  @id_param %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:index,
    summary: "List active and archived class types",
    responses: [
      ok:
        {"Class types", "application/json",
         %Schema{
           type: :object,
           properties: %{class_types: %Schema{type: :array, items: @class_type_schema}},
           required: [:class_types]
         }}
    ]
  )

  operation(:create,
    summary: "Create a class type",
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: @write_schema}}
    },
    responses: [
      created:
        {"Class type", "application/json",
         %Schema{
           type: :object,
           properties: %{class_type: @class_type_schema},
           required: [:class_type]
         }}
    ]
  )

  operation(:update,
    summary: "Rename or reorder an active class type",
    parameters: [@id_param],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: @write_schema}}
    },
    responses: [
      ok:
        {"Class type", "application/json",
         %Schema{
           type: :object,
           properties: %{class_type: @class_type_schema},
           required: [:class_type]
         }}
    ]
  )

  operation(:delete,
    summary: "Archive a class type and map future classes when necessary",
    parameters: [
      @id_param,
      %Parameter{
        name: :replacement_class_type_id,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok:
        {"Archived class type", "application/json",
         %Schema{
           type: :object,
           properties: %{class_type: @class_type_schema},
           required: [:class_type]
         }},
      conflict: {"Replacement required", "application/json", %Schema{type: :object}}
    ]
  )

  def index(conn, _params) do
    with {:ok, class_types} <- ListClassTypes.call(include_archived: true) do
      json(conn, %{class_types: class_types})
    end
  end

  def create(conn, params) do
    with {:ok, class_type} <- CreateClassType.call(body_params(conn, params)) do
      conn |> put_status(:created) |> json(%{class_type: class_type})
    end
  end

  def update(conn, params) do
    with {:ok, class_type} <-
           UpdateClassType.call(params[:id] || params["id"], body_params(conn, params)) do
      json(conn, %{class_type: class_type})
    end
  end

  def delete(conn, params) do
    with {:ok, class_type} <-
           ArchiveClassType.call(
             params[:id] || params["id"],
             params[:replacement_class_type_id] || params["replacement_class_type_id"]
           ) do
      json(conn, %{class_type: class_type})
    end
  end

  defp body_params(conn, params) do
    case conn.body_params do
      %{} = body when map_size(body) > 0 -> body
      _ -> params
    end
  end
end
