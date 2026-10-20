defmodule MilosTraining.Places.Neighbourhood do
  @moduledoc "A gazetteer place, a neighbourhood or a city, with its centroid (ADR-154)."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "places_neighbourhoods" do
    field :slug, :string
    field :kind, :string
    field :name, :string
    field :name_en, :string
    field :city_slug, :string
    field :country_code, :string
    field :latitude, :float
    field :longitude, :float
    field :radius_m, :integer
    field :search_key, :string

    timestamps(type: :utc_datetime_usec)
  end
end
