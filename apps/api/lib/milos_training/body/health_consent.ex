defmodule MilosTraining.Body.HealthConsent do
  @moduledoc "One grant of a health consent; withdrawing closes it (ADR-158, plan D8)."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_health_consents" do
    field :user_id, :binary_id
    field :scope, :string
    field :granted_at, :utc_datetime_usec
    field :withdrawn_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end
