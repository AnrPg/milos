defmodule MilosTraining.Buddies.SummaryGrant do
  @moduledoc "One grant of the coach's weekly wellness summary, or of cravings in it (ADR-160)."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "wellness_summary_grants" do
    field :user_id, :binary_id
    field :scope, :string
    field :granted_at, :utc_datetime_usec
    field :withdrawn_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end
