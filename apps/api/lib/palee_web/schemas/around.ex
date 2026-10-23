defmodule PaleeWeb.Schemas.Around do
  @moduledoc "OpenAPI schemas of Γύρω μου, «Η περιοχή μου» and the gazetteer (ADR-154, ADR-188)."

  alias Palee.Places
  alias PaleeWeb.Schemas.{Community, CommunityEvents, CommunityGroups}
  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}

  defp object(title, properties, required),
    do: %Schema{title: title, type: :object, properties: properties, required: required}

  defp list(schema), do: %Schema{type: :array, items: schema}
  defp string(opts \\ []), do: struct(Schema, Keyword.merge([type: :string], opts))
  defp number(opts \\ []), do: struct(Schema, Keyword.merge([type: :number], opts))
  defp integer(opts \\ []), do: struct(Schema, Keyword.merge([type: :integer], opts))
  defp strings, do: list(string())

  defdelegate body(schema), to: Community

  def error, do: %Schema{type: :object, additionalProperties: true}

  def kind, do: string(enum: Places.kinds())

  def filter do
    object(
      "AroundFilter",
      %{
        v: integer(description: "Filter version; #{Places.filter_version()} today"),
        radius_km: number(minimum: 0.5, maximum: 50, description: "Default 3"),
        neighbourhood_ids:
          list(@uuid)
          |> Map.put(:description, "Gazetteer places to search from, at most 5"),
        kinds: list(kind()) |> Map.put(:description, "Default events, boxes, clubs"),
        disciplines: strings(),
        when: string(enum: Places.filter_whens(), nullable: true),
        date_from: string(format: :date, nullable: true),
        date_to: string(format: :date, nullable: true),
        times: list(string(enum: Places.filter_times())),
        cost: list(string(enum: Places.filter_costs())),
        max_price_cents: integer(nullable: true, minimum: 0),
        audiences: strings(),
        languages: list(string(pattern: "^[a-z]{2}$")),
        amenities: strings()
      },
      []
    )
    |> Map.put(
      :description,
      "Every field is optional; the response echoes the normalised filter."
    )
  end

  def normalized_filter do
    filter()
    |> Map.put(:title, "AroundNormalizedFilter")
    |> Map.put(:required, [
      :v,
      :radius_km,
      :neighbourhood_ids,
      :kinds,
      :disciplines,
      :when,
      :date_from,
      :date_to,
      :times,
      :cost,
      :max_price_cents,
      :audiences,
      :languages,
      :amenities
    ])
  end

  def origin_request do
    object(
      "AroundOriginRequest",
      %{
        type: string(enum: ~w(area point place)),
        latitude: number(description: "point: the device position; rounded to 3 decimals"),
        longitude: number(),
        neighbourhood_id: %{@uuid | description: "place: a gazetteer place"},
        query: string(description: "place: a place name for the geocoder", maxLength: 200)
      },
      [:type]
    )
    |> Map.put(
      :description,
      "Where to start; left out, the filter's neighbourhoods, the saved area, then the member's box."
    )
  end

  def origin do
    object(
      "AroundOrigin",
      %{
        type: string(enum: Places.origin_types()),
        label: string(nullable: true),
        latitude: number(),
        longitude: number(),
        neighbourhood_ids: list(@uuid)
      },
      [:type, :label, :latitude, :longitude, :neighbourhood_ids]
    )
  end

  def search_request do
    object(
      "AroundSearchRequest",
      %{
        filter: filter(),
        origin: origin_request(),
        limit: integer(minimum: 1, maximum: 10, description: "Cards per section, default 5"),
        remember: %Schema{
          type: :boolean,
          description: "Remember the filter as last used (default true)"
        }
      },
      []
    )
  end

  def kind_request do
    object(
      "AroundKindRequest",
      %{
        filter: filter(),
        origin: origin_request(),
        cursor: string(nullable: true),
        limit: integer(minimum: 1, maximum: 50, description: "Default 20")
      },
      []
    )
  end

  def pins_request do
    object(
      "AroundPinsRequest",
      %{
        filter: filter(),
        bbox:
          object(
            "AroundViewport",
            %{west: number(), south: number(), east: number(), north: number()},
            [:west, :south, :east, :north]
          )
      },
      [:bbox]
    )
  end

  def box do
    object(
      "AroundBox",
      %{
        organization_id: @uuid,
        slug: string(),
        name: string(),
        logo_url: string(nullable: true),
        primary_color: string(nullable: true),
        cover_url: string(nullable: true),
        neighbourhood: string(nullable: true),
        city: string(nullable: true),
        latitude: number(),
        longitude: number(),
        disciplines: strings(),
        audiences: strings(),
        languages: strings(),
        amenities: strings(),
        takes_trials: %Schema{type: :boolean}
      },
      [
        :organization_id,
        :slug,
        :name,
        :latitude,
        :longitude,
        :disciplines,
        :audiences,
        :languages,
        :amenities,
        :takes_trials
      ]
    )
  end

  defp item(title, key, schema) do
    object(
      title,
      %{
        :distance_km =>
          number(description: "Kilometres, one decimal") |> Map.put(:nullable, true),
        key => schema
      },
      [:distance_km, key]
    )
  end

  defp section(title, item, extra \\ %{}) do
    object(
      title,
      Map.merge(
        %{
          total: integer(),
          items: list(item),
          next_cursor: string(nullable: true)
        },
        extra
      ),
      [:total, :items, :next_cursor] ++ Map.keys(extra)
    )
  end

  def event_item, do: item("AroundEventItem", :event, CommunityEvents.event())
  def box_item, do: item("AroundBoxItem", :box, box())
  def club_item, do: item("AroundClubItem", :club, CommunityGroups.open_club())
  def post_item, do: item("AroundPostItem", :post, Community.post())

  defp placement,
    do:
      string(
        enum: ~w(category collapsed),
        description:
          "collapsed: the viewer already has a gym; show one quiet «Άλλα box στην περιοχή (n)» line"
      )

  def events_section, do: section("AroundEventsSection", event_item())
  def boxes_section, do: section("AroundBoxesSection", box_item(), %{placement: placement()})
  def clubs_section, do: section("AroundClubsSection", club_item())
  def posts_section, do: section("AroundPostsSection", post_item())

  def search_response do
    object(
      "AroundSearchResponse",
      %{
        origin: origin(),
        filter: normalized_filter(),
        active_filters: integer(description: "For «Φίλτρα (n)»"),
        sections:
          object(
            "AroundSections",
            %{
              events: %{events_section() | nullable: true},
              boxes: %{boxes_section() | nullable: true},
              clubs: %{clubs_section() | nullable: true},
              posts: %{posts_section() | nullable: true}
            },
            [:events, :boxes, :clubs, :posts]
          )
          |> Map.put(:description, "A kind not asked for (or ruled out by cost) is null"),
        wider:
          list(
            object(
              "AroundWiderCount",
              %{
                radius_km: number(),
                total: integer(),
                by_kind: %Schema{type: :object, additionalProperties: integer()}
              },
              [:radius_km, :total, :by_kind]
            )
          )
          |> Map.put(:description, "Only when the search found few: how many at wider radii")
      },
      [:origin, :filter, :active_filters, :sections, :wider]
    )
  end

  def kind_response do
    object(
      "AroundKindResponse",
      %{
        kind: kind(),
        origin: origin(),
        total: integer(),
        items:
          list(%Schema{
            oneOf: [event_item(), box_item(), club_item(), post_item()]
          }),
        next_cursor: string(nullable: true),
        placement: placement()
      },
      [:kind, :origin, :total, :items, :next_cursor]
    )
  end

  def pins_response do
    object(
      "AroundPinsResponse",
      %{
        pins:
          list(
            object(
              "AroundPin",
              %{
                kind: kind(),
                id: %{@uuid | description: "Event, club or post id; the gym's id for a box"},
                latitude: number(),
                longitude: number(),
                title: string(nullable: true),
                slug: string(nullable: true, description: "Boxes: the public page's slug")
              },
              [:kind, :id, :latitude, :longitude, :title, :slug]
            )
          ),
        truncated: %Schema{type: :boolean, description: "More than the cap matched; zoom in"}
      },
      [:pins, :truncated]
    )
  end

  def neighbourhood do
    object(
      "Neighbourhood",
      %{
        id: @uuid,
        slug: string(),
        kind: string(enum: ~w(neighbourhood city)),
        name: string(),
        name_en: string(),
        city_slug: string(nullable: true),
        context:
          string(
            nullable: true,
            description: "What tells it apart: its city, or region and country"
          ),
        context_en: string(nullable: true),
        latitude: number(),
        longitude: number()
      },
      [
        :id,
        :slug,
        :kind,
        :name,
        :name_en,
        :city_slug,
        :context,
        :context_en,
        :latitude,
        :longitude
      ]
    )
  end

  def place_suggestion do
    object(
      "PlaceSuggestion",
      %{
        id: %{@uuid | description: "The gazetteer id, also of a suggested place once stored"},
        slug: string(),
        kind: string(enum: ~w(neighbourhood city address)),
        name: string(),
        name_en: string(),
        city_slug: string(nullable: true),
        context: string(nullable: true),
        context_en: string(nullable: true),
        latitude: number(),
        longitude: number(),
        ref:
          string(
            nullable: true,
            description:
              "Set on geocoder suggestions (ADR-188): POST it to /places/neighbourhoods/import before using the id"
          )
      },
      [
        :id,
        :slug,
        :kind,
        :name,
        :name_en,
        :city_slug,
        :context,
        :context_en,
        :latitude,
        :longitude
      ]
    )
  end

  def neighbourhoods_response,
    do:
      object(
        "NeighbourhoodsResponse",
        %{
          neighbourhoods: list(place_suggestion()),
          remote:
            string(
              enum: ~w(ok unavailable skipped),
              description: "Whether the worldwide geocoder answered, was down, or was not needed"
            )
        },
        [:neighbourhoods, :remote]
      )

  def place_import_request,
    do: object("PlaceImportRequest", %{ref: string(maxLength: 4_000)}, [:ref])

  def place_import_response,
    do: object("PlaceImportResponse", %{neighbourhood: neighbourhood()}, [:neighbourhood])

  def area_response,
    do:
      object("AroundAreaResponse", %{neighbourhoods: list(neighbourhood())}, [:neighbourhoods])
      |> Map.put(:description, "«Η περιοχή μου»; the first neighbourhood is the main one")

  def area_request,
    do:
      object(
        "AroundAreaRequest",
        %{neighbourhood_ids: list(@uuid) |> Map.put(:maxItems, Places.max_neighbourhoods())},
        [:neighbourhood_ids]
      )

  def around_visibility do
    object(
      "AroundVisibility",
      %{
        visible: %Schema{type: :boolean},
        has_area: %Schema{
          type: :boolean,
          description: "Public posts show only once «Η περιοχή μου» is set"
        }
      },
      [:visible, :has_area]
    )
    |> Map.put(
      :description,
      "«Φαίνομαι στο Γύρω μου»: your public posts show in Γύρω μου at your main neighbourhood"
    )
  end

  def around_visibility_request,
    do: object("AroundVisibilityRequest", %{visible: %Schema{type: :boolean}}, [:visible])
end
