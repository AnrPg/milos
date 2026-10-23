defmodule Palee.Perks.Rules.Eligibility do
  @moduledoc """
  Who may claim besides being a client: holders of one of `package_ids`
  (memberships are packages), members of one of `group_ids` (club
  groups), members for at least `min_tenure_days`. Empty means everyone.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :package_ids, {:array, Ecto.UUID}, default: []
    field :group_ids, {:array, Ecto.UUID}, default: []
    field :min_tenure_days, :integer
  end

  def changeset(eligibility, attrs) do
    eligibility
    |> cast(attrs, [:package_ids, :group_ids, :min_tenure_days])
    |> validate_length(:package_ids, max: 200)
    |> validate_length(:group_ids, max: 200)
    |> validate_number(:min_tenure_days, greater_than: 0, less_than_or_equal_to: 3_650)
  end
end
