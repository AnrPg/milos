defmodule PaleeWeb.AdminFacilityController do
  @moduledoc "Admin endpoints of the Facility context: locations and the check-in desk (ADR-097)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias Palee.Application.CheckInOpenGym
  alias Palee.Facility
  alias PaleeWeb.Schemas.Facility, as: FacilitySchemas
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Facility"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @location_schema FacilitySchemas.location_schema()
  @check_in_schema FacilitySchemas.check_in_schema()
  @error %Schema{type: :object, additionalProperties: true}

  @id_parameter %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  @location_response %Schema{
    type: :object,
    properties: %{location: @location_schema},
    required: [:location]
  }

  @location_body %RequestBody{
    required: true,
    content: %{"application/json" => %MediaType{schema: FacilitySchemas.location_params_schema()}}
  }

  operation(:index_locations,
    summary: "List locations, including archived ones",
    responses: [
      ok:
        {"Locations", "application/json",
         %Schema{
           type: :object,
           properties: %{locations: %Schema{type: :array, items: @location_schema}},
           required: [:locations]
         }}
    ]
  )

  def index_locations(conn, _params) do
    locations = Facility.list_locations(conn.assigns.tenant_context, include_archived: true)
    json(conn, %{locations: locations})
  end

  operation(:create_location,
    summary: "Create a location",
    request_body: @location_body,
    responses: [
      created: {"Location", "application/json", @location_response},
      unprocessable_entity: {"Invalid location", "application/json", @error}
    ]
  )

  def create_location(conn, _params) do
    with {:ok, location} <-
           Facility.create_location(conn.assigns.tenant_context, conn.body_params) do
      conn
      |> put_status(:created)
      |> json(%{location: location})
    end
  end

  operation(:update_location,
    summary: "Rename a location or change its address",
    parameters: [@id_parameter],
    request_body: @location_body,
    responses: [
      ok: {"Location", "application/json", @location_response},
      not_found: {"Location not found", "application/json", @error},
      unprocessable_entity: {"Invalid location", "application/json", @error}
    ]
  )

  def update_location(conn, %{id: id}) do
    with {:ok, location} <-
           Facility.update_location(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{location: location})
    end
  end

  operation(:archive_location,
    summary: "Archive a location; its past classes keep the reference",
    parameters: [@id_parameter],
    responses: [
      ok: {"Location", "application/json", @location_response},
      not_found: {"Location not found", "application/json", @error}
    ]
  )

  def archive_location(conn, %{id: id}) do
    with {:ok, location} <- Facility.archive_location(conn.assigns.tenant_context, id) do
      json(conn, %{location: location})
    end
  end

  @geocode_place FacilitySchemas.geocode_place_schema()
  @number %Schema{type: :number}
  @language_parameter %Parameter{
    name: :language,
    in: :query,
    required: false,
    schema: %Schema{type: :string, maxLength: 8}
  }

  operation(:search_addresses,
    summary: "Address suggestions for pinning a location (ADR-141)",
    parameters: [
      %Parameter{
        name: :q,
        in: :query,
        required: true,
        schema: %Schema{type: :string, maxLength: 200}
      },
      %Parameter{name: :near_latitude, in: :query, required: false, schema: @number},
      %Parameter{name: :near_longitude, in: :query, required: false, schema: @number},
      @language_parameter
    ],
    responses: [
      ok:
        {"Places", "application/json",
         %Schema{
           type: :object,
           properties: %{places: %Schema{type: :array, items: @geocode_place}},
           required: [:places]
         }},
      service_unavailable: {"Geocoder unavailable", "application/json", @error}
    ]
  )

  def search_addresses(conn, %{q: query} = params) do
    near =
      case params do
        %{near_latitude: lat, near_longitude: lng} -> {lat, lng}
        _without -> nil
      end

    with {:ok, places} <-
           Facility.search_addresses(query, near: near, language: Map.get(params, :language)) do
      json(conn, %{places: places})
    end
  end

  operation(:reverse_geocode,
    summary: "The address and neighbourhood at a map point (ADR-141)",
    parameters: [
      %Parameter{name: :latitude, in: :query, required: true, schema: @number},
      %Parameter{name: :longitude, in: :query, required: true, schema: @number},
      @language_parameter
    ],
    responses: [
      ok:
        {"Place", "application/json",
         %Schema{
           type: :object,
           properties: %{place: %Schema{@geocode_place | nullable: true}},
           required: [:place]
         }},
      service_unavailable: {"Geocoder unavailable", "application/json", @error}
    ]
  )

  def reverse_geocode(conn, %{latitude: lat, longitude: lng} = params) do
    with {:ok, place} <-
           Facility.reverse_geocode(lat, lng, language: Map.get(params, :language)) do
      json(conn, %{place: place})
    end
  end

  operation(:resolve_map_link,
    summary: "The pin and address behind a pasted Google Maps link (ADR-141)",
    parameters: [
      %Parameter{
        name: :url,
        in: :query,
        required: true,
        schema: %Schema{type: :string, maxLength: 2_000}
      },
      @language_parameter
    ],
    responses: [
      ok:
        {"Place", "application/json",
         %Schema{type: :object, properties: %{place: @geocode_place}, required: [:place]}},
      unprocessable_entity: {"Not a usable map link", "application/json", @error}
    ]
  )

  def resolve_map_link(conn, %{url: url} = params) do
    with {:ok, place} <- Facility.resolve_map_link(url, language: Map.get(params, :language)) do
      json(conn, %{place: place})
    end
  end

  operation(:index_check_ins,
    summary: "List open-gym check-ins of a day or a member",
    parameters: [
      %Parameter{
        name: :date,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :date}
      },
      %Parameter{
        name: :user_id,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok:
        {"Check-ins", "application/json",
         %Schema{
           type: :object,
           properties: %{check_ins: %Schema{type: :array, items: @check_in_schema}},
           required: [:check_ins]
         }}
    ]
  )

  def index_check_ins(conn, params) do
    filters = %{date: Map.get(params, :date), user_id: Map.get(params, :user_id)}
    json(conn, %{check_ins: Facility.list_check_ins(conn.assigns.tenant_context, filters)})
  end

  operation(:create_check_in,
    summary: "Check a member in to open gym from the desk",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              user_id: %Schema{type: :string, format: :uuid},
              location_id: %Schema{type: :string, format: :uuid, nullable: true}
            },
            required: [:user_id]
          }
        }
      }
    },
    responses: [
      created:
        {"Check-in", "application/json",
         %Schema{
           type: :object,
           properties: %{check_in: @check_in_schema},
           required: [:check_in]
         }},
      forbidden: {"Finance entitlement denied", "application/json", @error}
    ]
  )

  def create_check_in(conn, _params) do
    staff = GuardianPlug.current_resource(conn)
    user_id = Map.get(conn.body_params, :user_id)
    params = %{"location_id" => Map.get(conn.body_params, :location_id)}

    with {:ok, check_in} <-
           CheckInOpenGym.call(conn.assigns.tenant_context, staff, user_id, params) do
      conn
      |> put_status(:created)
      |> json(%{check_in: check_in})
    end
  end
end
