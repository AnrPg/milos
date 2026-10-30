defmodule Palee.Partners.Profile do
  @moduledoc """
  A person's Partners profile (ADR-169, one per account since ADR-280):
  their opt-in, the 18+ confirmation, whether the card names their box,
  level, times, goals, disciplines, an optional line about themselves, the
  optional gender and preference used only to honour preferences (never
  shown), and `paused_at` (the Ρυθμίσεις switch).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Partners.Domain.ProfilePolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "partner_profiles" do
    field :user_id, :binary_id
    field :active, :boolean, default: true
    field :adult_confirmed_at, :utc_datetime_usec
    field :show_box, :boolean, default: true
    field :level, :string
    field :times, {:array, :string}, default: []
    field :goals, {:array, :string}, default: []
    field :disciplines, {:array, :string}, default: []
    field :about, :string
    field :gender, :string
    field :gender_preference, :string, default: "any"
    field :paused_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @editable ~w(active show_box level times goals disciplines about gender gender_preference)a

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:user_id, :adult_confirmed_at | @editable])
    |> validate_required([:user_id, :adult_confirmed_at])
    |> validate()
    |> unique_constraint(:user_id)
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [:paused_at | @editable])
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
