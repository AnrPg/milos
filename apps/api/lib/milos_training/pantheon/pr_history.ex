defmodule MilosTraining.Pantheon.PRHistory do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_pr_history" do
    field(:organization_id, :binary_id)
    field(:pr_record_id, :binary_id)
    field(:score, :decimal)
    field(:beaten_on, :date)
    field(:supporting_metrics, :map, default: %{})

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(history \\ %__MODULE__{}, params) do
    history
    |> cast(params, [
      :organization_id,
      :pr_record_id,
      :score,
      :beaten_on,
      :supporting_metrics
    ])
    |> validate_required([:pr_record_id, :score, :beaten_on])
    |> foreign_key_constraint(:pr_record_id)
  end
end
