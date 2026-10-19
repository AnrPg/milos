defmodule MilosTraining.Facility.Location do
  @moduledoc "A gym location of an organization (ADR-097), with where it is and when it is open (ADR-141)."

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Facility.Domain.PlacePolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @place_fields [
    :latitude,
    :longitude,
    :neighbourhood,
    :city,
    :country_code,
    :opening_hours,
    :accessibility
  ]

  schema "facility_locations" do
    field :organization_id, :binary_id
    field :name, :string
    field :address, :string
    field :latitude, :float
    field :longitude, :float
    field :neighbourhood, :string
    field :city, :string
    field :country_code, :string
    field :opening_hours, {:array, :map}, default: []
    field :accessibility, {:array, :string}, default: []
    field :archived_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(location \\ %__MODULE__{}, params) do
    location
    |> cast(params, [:organization_id, :name, :address | @place_fields])
    |> validate_required([:organization_id])
    |> validate_fields()
  end

  def update_changeset(location, params) do
    location
    |> cast(params, [:name, :address | @place_fields])
    |> validate_fields()
  end

  def archive_changeset(location, archived_at), do: change(location, archived_at: archived_at)

  defp validate_fields(changeset) do
    changeset
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 80)
    |> validate_length(:address, max: 300)
    |> validate_place()
    |> unique_constraint(:name, name: :facility_locations_organization_name_index)
    |> check_constraint(:latitude, name: :facility_locations_coordinates_check)
  end

  defp validate_place(changeset) do
    changeset
    |> update_change(:latitude, &PlacePolicy.round_coordinate/1)
    |> update_change(:longitude, &PlacePolicy.round_coordinate/1)
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> validate_coordinates_pair()
    |> update_change(:neighbourhood, &PlacePolicy.normalize_name/1)
    |> update_change(:city, &PlacePolicy.normalize_name/1)
    |> validate_length(:neighbourhood, max: 80)
    |> validate_length(:city, max: 80)
    |> update_change(:country_code, &PlacePolicy.normalize_country_code/1)
    |> validate_change(:country_code, fn :country_code, code ->
      if is_nil(code) or PlacePolicy.valid_country_code?(code),
        do: [],
        else: [country_code: "must be an ISO 3166-1 alpha-2 code"]
    end)
    |> validate_subset(:accessibility, PlacePolicy.accessibility_features())
    |> update_change(:accessibility, &Enum.uniq/1)
    |> validate_opening_hours()
  end

  defp validate_coordinates_pair(changeset) do
    case {get_field(changeset, :latitude), get_field(changeset, :longitude)} do
      {nil, nil} -> changeset
      {lat, lng} when is_float(lat) and is_float(lng) -> changeset
      _half -> add_error(changeset, :latitude, "latitude and longitude go together")
    end
  end

  defp validate_opening_hours(changeset) do
    case fetch_change(changeset, :opening_hours) do
      {:ok, spans} ->
        case PlacePolicy.normalize_opening_hours(spans || []) do
          {:ok, spans} -> put_change(changeset, :opening_hours, spans)
          {:error, reason} -> add_error(changeset, :opening_hours, Atom.to_string(reason))
        end

      :error ->
        changeset
    end
  end
end
