defmodule Palee.Community.Event do
  @moduledoc """
  One occurrence of an event in a club (ADR-153): when and where, how many
  can come, what it costs, who may come besides the club's members. A weekly
  repeat is a run of events sharing `series_id`, each with its own attendees.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.TimeZones.ZonedTime

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
    :audience,
    :guest_pass_allowed,
    :guests_per_member,
    :good_for_friends,
    :cover_media_id,
    :time_zone
  ]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "community_events" do
    field :organization_id, :binary_id, read_after_writes: true
    field :club_id, :binary_id
    field :channel_id, :binary_id
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
    # ADR-185: who it is for: a member `group`, the `club`, or everyone
    # (`open`, always the same as `open_to_non_members`).
    field :audience, :string, default: "club"
    field :guest_pass_allowed, :boolean, default: false
    field :guests_per_member, :integer, default: 1
    field :good_for_friends, :boolean, default: false
    field :cover_media_id, :binary_id
    # ADR-179: the zone of an event held away from its gym; nil: the gym's.
    field :time_zone, :string
    field :series_id, :binary_id
    field :cancelled_at, :utc_datetime_usec
    field :cancel_reason, :string
    field :reminder_sent_at, :utc_datetime_usec
    field :trial_offer_sent_at, :utc_datetime_usec
    field :post_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @audiences ~w(group club open)

  def editable_fields, do: @editable
  def audiences, do: @audiences

  @doc "ADR-179: the clock the event is planned on: its own zone, else its gym's."
  def time_zone(%{time_zone: zone}, _gym_zone) when is_binary(zone) and zone != "", do: zone
  def time_zone(_event, gym_zone), do: gym_zone

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :organization_id,
      :club_id,
      :channel_id,
      :created_by_id,
      :series_id | @editable
    ])
    |> validate_required([:club_id])
    |> default_group_audience(attrs)
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
    |> validate_required([:title, :starts_at, :ends_at, :price_cents, :currency, :audience])
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
    |> update_change(:time_zone, &trim/1)
    |> validate_change(:time_zone, fn :time_zone, zone ->
      if ZonedTime.valid?(zone), do: [], else: [time_zone: "is not a known time zone"]
    end)
    |> validate_place()
    |> validate_times()
    |> sync_audience()
    |> validate_good_for_friends()
    |> check_constraint(:good_for_friends, name: :community_events_good_for_friends_check)
    |> check_constraint(:starts_at, name: :community_events_time_check)
    |> check_constraint(:location_id, name: :community_events_place_check)
    |> check_constraint(:capacity, name: :community_events_limits_check)
    |> check_constraint(:audience, name: :community_events_audience_check)
    |> foreign_key_constraint(:channel_id, name: :community_events_channel_id_fkey)
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

  # A group's event created without an audience stays with the group, as
  # before ADR-185.
  defp default_group_audience(changeset, attrs) do
    explicit? = is_binary(Map.get(attrs, :audience, Map.get(attrs, "audience")))

    if explicit? or is_nil(get_field(changeset, :channel_id)) or
         get_field(changeset, :open_to_non_members),
       do: changeset,
       else: put_change(changeset, :audience, "group")
  end

  # ADR-185: `audience` and `open_to_non_members` always agree. Whichever
  # was asked wins; a group's audience needs a group.
  defp sync_audience(changeset) do
    changeset =
      cond do
        is_binary((changeset.params || %{})["audience"]) ->
          put_change(
            changeset,
            :open_to_non_members,
            get_field(changeset, :audience) == "open"
          )

        Map.has_key?(changeset.changes, :open_to_non_members) ->
          put_change(changeset, :audience, audience_for_open(changeset))

        true ->
          changeset
      end

    changeset
    |> validate_inclusion(:audience, @audiences)
    |> then(fn changeset ->
      if get_field(changeset, :audience) == "group" and is_nil(get_field(changeset, :channel_id)),
        do: add_error(changeset, :audience, "only a member group's event is for the group"),
        else: changeset
    end)
  end

  defp audience_for_open(changeset) do
    cond do
      get_field(changeset, :open_to_non_members) -> "open"
      get_field(changeset, :audience) == "open" and get_field(changeset, :channel_id) -> "group"
      get_field(changeset, :audience) == "open" -> "club"
      true -> get_field(changeset, :audience) || "club"
    end
  end

  # «Καλό για φίλους» (ADR-156) only on an event a friend can come to.
  defp validate_good_for_friends(changeset) do
    friends_can_come? =
      get_field(changeset, :open_to_non_members) or get_field(changeset, :guest_pass_allowed)

    if get_field(changeset, :good_for_friends) and not friends_can_come? do
      add_error(changeset, :good_for_friends, "friends can't come to this event")
    else
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
