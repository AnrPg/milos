defmodule MilosTrainingWeb.MyPlacesController do
  @moduledoc "Locations the user can book across their gyms, for the Πρόγραμμα location picker."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.ListBookablePlaces
  alias OpenApiSpex.Schema

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Me"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, [json_render_error_v2: true] when action in [:index]

  @place_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      name: %Schema{type: :string},
      address: %Schema{type: :string, nullable: true},
      neighbourhood: %Schema{type: :string, nullable: true},
      city: %Schema{type: :string, nullable: true},
      latitude: %Schema{type: :number, nullable: true},
      longitude: %Schema{type: :number, nullable: true},
      home: %Schema{type: :boolean, description: "The user's home location in that gym"},
      distance_km: %Schema{type: :number, nullable: true},
      organization: %Schema{
        type: :object,
        properties: %{
          id: %Schema{type: :string, format: :uuid},
          slug: %Schema{type: :string},
          name: %Schema{type: :string}
        },
        required: [:id, :slug, :name]
      }
    },
    required: [:id, :name, :home, :distance_km, :organization]
  }

  operation(:index,
    summary: "Locations the user can book, nearest first",
    description:
      "Distance is from lat/lng when given (the device position), otherwise from the user's home location.",
    parameters: [
      lat: [in: :query, schema: %Schema{type: :number, minimum: -90, maximum: 90}],
      lng: [in: :query, schema: %Schema{type: :number, minimum: -180, maximum: 180}]
    ],
    responses: [
      ok:
        {"Places", "application/json",
         %Schema{
           type: :object,
           properties: %{places: %Schema{type: :array, items: @place_schema}},
           required: [:places]
         }}
    ]
  )

  def index(conn, params) do
    user = Guardian.Plug.current_resource(conn)
    json(conn, %{places: ListBookablePlaces.call(user.id, near(params))})
  end

  defp near(%{lat: lat, lng: lng}) when is_number(lat) and is_number(lng), do: {lat, lng}
  defp near(_params), do: nil
end
