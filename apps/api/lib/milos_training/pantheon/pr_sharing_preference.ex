defmodule MilosTraining.Pantheon.PRSharingPreference do
  @moduledoc """
  Per-user PR sharing preference (ADR-111). Absence of a row means the
  defaults: coaches of the gyms a PR was recorded in may read it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:user_id, :binary_id, autogenerate: false}

  schema "user_pr_sharing_preferences" do
    field(:coach_visibility, :boolean, default: true)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(preference, params) do
    preference
    |> cast(params, [:user_id, :coach_visibility])
    |> validate_required([:user_id, :coach_visibility])
  end
end
