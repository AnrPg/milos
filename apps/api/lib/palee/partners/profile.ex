defmodule Palee.Partners.Profile do
  @moduledoc """
  A member's Partners profile in one club (ADR-169): their opt-in, level,
  times, goals, an optional line about themselves, and the optional gender
  and preference used only to honour preferences (never shown). Staff
  suspend it after a report.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Partners.Domain.ProfilePolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "partner_profiles" do
    field :organization_id, :binary_id, read_after_writes: true
    field :club_id, :binary_id
    field :user_id, :binary_id
    field :active, :boolean, default: true
    field :level, :string
    field :times, {:array, :string}, default: []
    field :goals, {:array, :string}, default: []
    field :disciplines, {:array, :string}, default: []
    field :about, :string
    field :gender, :string
    field :gender_preference, :string, default: "any"
    field :suspended_at, :utc_datetime_usec
    field :suspended_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @editable ~w(active level times goals disciplines about gender gender_preference)a

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:organization_id, :club_id, :user_id | @editable])
    |> validate_required([:club_id, :user_id])
    |> validate()
    |> unique_constraint([:club_id, :user_id])
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, @editable ++ [:suspended_at, :suspended_by_id])
    |> validate()
  end

  defp validate(changeset) do
    changeset
    |> validate_required([:level, :gender_preference])
    |> validate_inclusion(:level, ProfilePolicy.levels())
    |> validate_subset(:times, ProfilePolicy.times())
    |> validate_subset(:goals, ProfilePolicy.goals())
    |> validate_length(:times, min: 1, max: length(ProfilePolicy.times()))
    |> validate_length(:goals, min: 1, max: ProfilePolicy.max_goals())
    |> validate_length(:disciplines, max: ProfilePolicy.max_disciplines())
    |> validate_length(:about, max: ProfilePolicy.about_max())
    |> validate_inclusion(:gender, ProfilePolicy.genders())
    |> validate_inclusion(:gender_preference, ProfilePolicy.gender_preferences())
  end
end
