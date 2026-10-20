defmodule MilosTraining.Community.Event do
  @moduledoc """
  One occurrence of an event in a club (ADR-153): when and where, how many
  can come, what it costs, who may come besides the club's members. A weekly
  repeat is a run of events sharing `series_id`, each with its own attendees.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @editable [
    :title,
    :description,
    :starts_at,
    :ends_at,
    :location_id,
    :place_name,
    :address,
    :latitude,
    :longitude,
    :capacity,
    :price_cents,
    :currency,
    :open_to_non_members,
    :guest_pass_allowed,
    :guests_per_member,
    :cover_media_id
  ]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "community_events" do
    field :organization_id, :binary_id, read_after_writes: true
    field :club_id, :binary_id
    field :created_by_id, :binary_id
    field :title, :string
    field :description, :string
    field :starts_at, :utc_datetime_usec
    field :ends_at, :utc_datetime_usec
    field :location_id, :binary_id
    field :place_name, :string
    field :address, :string
    field :latitude, :float
    field :longitude, :float
    field :capacity, :integer
    field :price_cents, :integer, default: 0
    field :currency, :string, default: "EUR"
    field :open_to_non_members, :boolean, default: false
    field :guest_pass_allowed, :boolean, default: false
    field :guests_per_member, :integer, default: 1
    field :cover_media_id, :binary_id
    field :series_id, :binary_id
    field :cancelled_at, :utc_datetime_usec
    field :cancel_reason, :string
    field :reminder_sent_at, :utc_datetime_usec
    field :trial_offer_sent_at, :utc_datetime_usec
    field :post_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def editable_fields, do: @editable

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :club_id, :created_by_id, :series_id | @editable])
    |> validate_required([:club_id])
    |> validate()
  end

  def update_changeset(event, attrs) do
    event
    |> cast(attrs, @editable ++ [:post_id, :reminder_sent_at])
    |> validate()
  end

  def lifecycle_changeset(event, attrs),
    do:
      cast(event, attrs, [:cancelled_at, :cancel_reason, :reminder_sent_at, :trial_offer_sent_at])

  defp validate(changeset) do
    changeset
    |> update_change(:title, &trim/1)
    |> update_change(:description, &trim/1)
    |> update_change(:place_name, &trim/1)
    |> update_change(:address, &trim/1)
    |> update_change(:currency, &(&1 && String.upcase(&1)))
    |> validate_required([:title, :starts_at, :ends_at, :price_cents, :currency])
    |> validate_length(:title, max: 120)
    |> validate_length(:description, max: 4_000)
    |> validate_length(:place_name, max: 120)
    |> validate_length(:address, max: 200)
    |> validate_format(:currency, ~r/^[A-Z]{3}$/)
    |> validate_number(:capacity, greater_than: 0, less_than_or_equal_to: 10_000)
    |> validate_number(:price_cents,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 10_000_000
    )
    |> validate_number(:guests_per_member, greater_than: 0, less_than_or_equal_to: 10)
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> validate_place()
    |> validate_times()
    |> check_constraint(:starts_at, name: :community_events_time_check)
    |> check_constraint(:location_id, name: :community_events_place_check)
    |> check_constraint(:capacity, name: :community_events_limits_check)
    |> foreign_key_constraint(:location_id)
    |> foreign_key_constraint(:club_id, name: :community_events_club_id_fkey)
  end

  # Somewhere to go: a location of the box or a named place, never both.
  defp validate_place(changeset) do
    location? = not is_nil(get_field(changeset, :location_id))
    place? = not is_nil(get_field(changeset, :place_name))
    coordinates = {get_field(changeset, :latitude), get_field(changeset, :longitude)}

    cond do
      location? and place? ->
        add_error(changeset, :place_name, "choose a location or a place")

      not location? and not place? ->
        add_error(changeset, :location_id, "can't be blank")

      match?({nil, lng} when not is_nil(lng), coordinates) ->
        add_error(changeset, :latitude, "can't be blank")

      match?({lat, nil} when not is_nil(lat), coordinates) ->
        add_error(changeset, :longitude, "can't be blank")

      true ->
        changeset
    end
  end

  defp validate_times(changeset) do
    with %DateTime{} = starts_at <- get_field(changeset, :starts_at),
         %DateTime{} = ends_at <- get_field(changeset, :ends_at) do
      cond do
        DateTime.compare(ends_at, starts_at) != :gt ->
          add_error(changeset, :ends_at, "must be after the start")

        DateTime.diff(ends_at, starts_at, :second) > 7 * 86_400 ->
          add_error(changeset, :ends_at, "must be within 7 days of the start")

        true ->
          changeset
      end
    else
      _missing -> changeset
    end
  end

  defp trim(nil), do: nil
  defp trim(value), do: value |> String.trim() |> then(&if(&1 == "", do: nil, else: &1))
end
