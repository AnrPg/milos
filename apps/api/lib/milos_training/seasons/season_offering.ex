defmodule MilosTraining.Seasons.SeasonOffering do
  @moduledoc """
  A season a gym sells (ADR-167): a fixed-length programme with a start date,
  a number of weeks and a capacity. The programme is an ordered list of
  `%{"day" => 0.., "workout_id" => uuid}` (day 0 is the start date); an
  optional membership package is what a confirmed participant is granted
  through Finance.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Seasons.Domain.SeasonRules

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @editable ~w(title description welcome_message starts_on weeks capacity price_cents currency
               membership_package_id programme coach_ids)a

  @type t :: %__MODULE__{}

  schema "season_offerings" do
    field :organization_id, :binary_id, read_after_writes: true
    field :title, :string
    field :description, :string
    field :welcome_message, :string
    field :starts_on, :date
    field :weeks, :integer
    field :capacity, :integer
    field :price_cents, :integer, default: 0
    field :currency, :string, default: "EUR"
    field :membership_package_id, :binary_id
    field :programme, {:array, :map}, default: []
    field :coach_ids, {:array, :binary_id}, default: []
    field :status, :string, default: "draft"
    field :channel_id, :binary_id
    field :created_by_id, :binary_id
    field :published_at, :utc_datetime_usec
    field :cancelled_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def editable_fields, do: @editable

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :created_by_id, :status, :published_at | @editable])
    |> validate()
  end

  def update_changeset(offering, attrs) do
    offering
    |> cast(attrs, [:status, :channel_id, :published_at, :cancelled_at | @editable])
    |> validate()
  end

  defp validate(changeset) do
    changeset
    |> update_change(:title, &String.trim/1)
    |> update_change(:description, &blank_to_nil/1)
    |> update_change(:welcome_message, &blank_to_nil/1)
    |> validate_required([:title, :starts_on, :weeks, :capacity, :price_cents, :status])
    |> validate_length(:title, min: 2, max: 80)
    |> validate_length(:description, max: 2000)
    |> validate_length(:welcome_message, max: 1000)
    |> validate_number(:weeks, greater_than_or_equal_to: 1, less_than_or_equal_to: 52)
    |> validate_number(:capacity, greater_than_or_equal_to: 1, less_than_or_equal_to: 500)
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
    |> validate_inclusion(:status, SeasonRules.statuses())
    |> validate_programme()
    |> foreign_key_constraint(:membership_package_id)
    |> check_constraint(:title, name: :season_offerings_limits_check)
  end

  defp validate_programme(changeset) do
    weeks = get_field(changeset, :weeks)

    case SeasonRules.normalize_programme(get_field(changeset, :programme) || [], weeks) do
      {:ok, programme} -> put_change(changeset, :programme, programme)
      {:error, message} -> add_error(changeset, :programme, message)
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: value |> String.trim() |> then(&if(&1 == "", do: nil, else: &1))
end
