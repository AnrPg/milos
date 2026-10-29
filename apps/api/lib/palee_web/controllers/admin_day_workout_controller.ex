defmodule PaleeWeb.AdminDayWorkoutController do
  @moduledoc "ADR-230: the WOD of a whole day, inherited by its classes."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}
  alias Palee.Application.DayWorkouts

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Schedule"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate,
       [json_render_error_v2: true]
       when action in [:index, :preview, :put, :follow_day]

  @max_days 62

  @day_workout_schema %Schema{
    type: :object,
    additionalProperties: true,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      local_date: %Schema{type: :string, format: :date},
      class_type_id: %Schema{
        type: :string,
        format: :uuid,
        nullable: true,
        description: "Null: every class (events only by type)"
      },
      location_id: %Schema{
        type: :string,
        format: :uuid,
        nullable: true,
        description: "Null: every branch"
      },
      master_workout_id: %Schema{type: :string, format: :uuid},
      workout: %Schema{
        type: :object,
        nullable: true,
        properties: %{
          id: %Schema{type: :string, format: :uuid},
          title: %Schema{type: :string},
          type: %Schema{type: :string, nullable: true}
        }
      }
    },
    required: [:id, :local_date, :class_type_id, :location_id, :master_workout_id]
  }

  @request_schema %Schema{
    type: :object,
    additionalProperties: false,
    properties: %{
      date: %Schema{type: :string, format: :date, description: "The gym's own date"},
      class_type_ids: %Schema{
        type: :array,
        items: %Schema{type: :string, format: :uuid},
        maxItems: 50,
        description: "Empty or missing: every class of the day"
      },
      location_id: %Schema{
        type: :string,
        format: :uuid,
        nullable: true,
        description: "Null: every branch"
      },
      master_workout_id: %Schema{type: :string, format: :uuid},
      replace_own: %Schema{
        type: :boolean,
        description: "Also replace the WODs set on single classes in this scope"
      }
    },
    required: [:date, :master_workout_id]
  }

  @class_summary %Schema{
    type: :object,
    additionalProperties: true,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      name: %Schema{type: :string},
      scheduled_at: %Schema{type: :string, format: :"date-time"},
      class_type_name: %Schema{type: :string, nullable: true}
    },
    required: [:id, :name, :scheduled_at]
  }

  @id_param %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:index,
    summary: "Day WODs of a date range",
    parameters: [
      from: [in: :query, required: true, schema: %Schema{type: :string, format: :date}],
      to: [in: :query, required: true, schema: %Schema{type: :string, format: :date}]
    ],
    responses: [
      ok:
        {"Day WODs", "application/json",
         %Schema{
           type: :object,
           properties: %{day_workouts: %Schema{type: :array, items: @day_workout_schema}},
           required: [:day_workouts]
         }}
    ]
  )

  operation(:preview,
    summary: "What setting a day WOD would change",
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: @request_schema}}
    },
    responses: [
      ok:
        {"Classes by outcome", "application/json",
         %Schema{
           type: :object,
           properties: %{
             inherit: %Schema{type: :array, items: @class_summary},
             own: %Schema{type: :array, items: @class_summary},
             started: %Schema{type: :array, items: @class_summary}
           },
           required: [:inherit, :own, :started]
         }}
    ]
  )

  operation(:put,
    summary: "Set the WOD of a day",
    description:
      "ADR-230: every class of the date (or of the given class types) inherits the WOD " <>
        "unless it has its own; classes created later that day inherit it too.",
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: @request_schema}}
    },
    responses: [
      ok:
        {"Day WODs set", "application/json",
         %Schema{
           type: :object,
           properties: %{
             day_workouts: %Schema{type: :array, items: @day_workout_schema},
             changed_count: %Schema{type: :integer}
           },
           required: [:day_workouts, :changed_count]
         }}
    ]
  )

  operation(:delete,
    summary: "Remove a day WOD",
    parameters: [@id_param],
    responses: [
      ok:
        {"Removed", "application/json",
         %Schema{
           type: :object,
           properties: %{
             day_workout: @day_workout_schema,
             changed_count: %Schema{type: :integer}
           },
           required: [:day_workout, :changed_count]
         }}
    ]
  )

  operation(:follow_day,
    summary: "Give a class the day's WOD in place of its own",
    parameters: [@id_param],
    responses: [
      ok:
        {"Slot", "application/json",
         %Schema{
           type: :object,
           properties: %{slot: %Schema{type: :object, additionalProperties: true}},
           required: [:slot]
         }}
    ]
  )

  def index(conn, params) do
    with {:ok, from} <- date(params, :from),
         {:ok, to} <- date(params, :to),
         :ok <- valid_range(from, to) do
      json(conn, %{day_workouts: DayWorkouts.list(conn.assigns.tenant_context, from, to)})
    end
  end

  def preview(conn, _params) do
    with {:ok, result} <- DayWorkouts.preview(conn.assigns.tenant_context, body(conn)) do
      json(conn, result)
    end
  end

  def put(conn, _params) do
    with {:ok, result} <- DayWorkouts.set(conn.assigns.tenant_context, body(conn)) do
      json(conn, result)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, result} <- DayWorkouts.clear(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end

  def follow_day(conn, params) do
    id = params["id"] || params[:id]

    with {:ok, slot} <- DayWorkouts.reset_class(conn.assigns.tenant_context, id) do
      json(conn, %{slot: slot})
    end
  end

  defp date(params, key) do
    case Map.get(params, key) || Map.get(params, Atom.to_string(key)) do
      %Date{} = date -> {:ok, date}
      value when is_binary(value) -> parse(value)
      _missing -> {:error, :invalid_date}
    end
  end

  defp parse(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _invalid -> {:error, :invalid_date}
    end
  end

  defp valid_range(from, to) do
    if Date.compare(from, to) != :gt and Date.diff(to, from) <= @max_days,
      do: :ok,
      else: {:error, :invalid_date}
  end

  # CastAndValidate casts the body into atom keys; the use case reads both.
  defp body(conn) do
    case conn.body_params do
      %{} = params when map_size(params) > 0 -> params
      _empty -> %{}
    end
  end
end
