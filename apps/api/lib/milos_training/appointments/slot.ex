defmodule MilosTraining.Appointments.Slot do
  @moduledoc "A bookable PT session or assessment published by a coach (ADR-098)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "appointment_slots" do
    field :organization_id, :binary_id
    field :coach_id, :binary_id
    field :kind, :string
    field :format, :string
    field :starts_at, :utc_datetime_usec
    field :duration_minutes, :integer
    field :capacity, :integer, default: 1
    field :location_id, :binary_id
    field :notes, :string
    # ADR-170: an independent coach trains in person (a gym, a park) or online.
    field :mode, :string, default: "in_person"
    field :meeting_url, :string
    field :cancelled_at, :utc_datetime_usec
    field :created_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(params) do
    %__MODULE__{}
    |> cast(params, [
      :organization_id,
      :coach_id,
      :kind,
      :format,
      :starts_at,
      :duration_minutes,
      :capacity,
      :location_id,
      :notes,
      :mode,
      :meeting_url,
      :created_by_id
    ])
    |> validate_required([
      :organization_id,
      :coach_id,
      :kind,
      :format,
      :starts_at,
      :duration_minutes
    ])
    |> validate_inclusion(:kind, ["pt_session", "assessment"])
    |> validate_inclusion(:format, ["one_to_one", "semi_private"])
    |> validate_number(:duration_minutes,
      greater_than_or_equal_to: 15,
      less_than_or_equal_to: 240
    )
    |> validate_capacity()
    |> validate_length(:notes, max: 1000)
    |> validate_inclusion(:mode, ["in_person", "online"])
    |> validate_meeting_url()
    |> foreign_key_constraint(:location_id)
    |> check_constraint(:capacity, name: :appointment_slots_format)
  end

  def cancel_changeset(slot, cancelled_at), do: change(slot, cancelled_at: cancelled_at)

  # An online session may carry its call link (https only); in person never does.
  defp validate_meeting_url(changeset) do
    case {get_field(changeset, :mode), get_field(changeset, :meeting_url)} do
      {_mode, nil} ->
        changeset

      {"online", url} ->
        changeset
        |> validate_length(:meeting_url, max: 500)
        |> validate_change(:meeting_url, fn :meeting_url, _value ->
          if https_url?(url), do: [], else: [meeting_url: "must be an https:// link"]
        end)

      {_in_person, _url} ->
        add_error(changeset, :meeting_url, "only an online session has a link")
    end
  end

  defp https_url?(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> true
      _other -> false
    end
  end

  defp validate_capacity(changeset) do
    case get_field(changeset, :format) do
      "one_to_one" ->
        put_change(changeset, :capacity, 1)

      "semi_private" ->
        validate_number(changeset, :capacity,
          greater_than_or_equal_to: 2,
          less_than_or_equal_to: 4
        )

      _other ->
        changeset
    end
  end
end
