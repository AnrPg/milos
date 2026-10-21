defmodule MilosTraining.Insights.Insight do
  @moduledoc "One person's latest result of one insight rule (ADR-166)."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "user_insights" do
    field(:user_id, :binary_id)
    field(:rule, :string)
    field(:status, :string)
    field(:period_start, :date)
    field(:period_end, :date)
    field(:value, :map, default: %{})
    field(:fingerprint, :string)
    field(:computed_at, :utc_datetime_usec)
    field(:dismissed_fingerprint, :string)
    field(:dismissed_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end
end
