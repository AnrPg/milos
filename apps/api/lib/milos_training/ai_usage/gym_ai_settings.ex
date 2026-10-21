defmodule MilosTraining.AiUsage.GymAiSettings do
  @moduledoc """
  A gym's AI settings (ADR-174): its own provider key, encrypted at rest and
  never returned over the API, an optional model override and the per-feature
  switches (scaling suggestions, off by default). One row per gym, next to the
  usage it meters (ADR-152).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.Infrastructure.Security.EncryptedBinary

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organization_ai_settings" do
    field :organization_id, :binary_id
    field :provider, :string, default: "anthropic"
    field :api_key, EncryptedBinary, redact: true
    field :api_key_last4, :string
    field :key_status, :string, default: "unknown"
    field :key_checked_at, :utc_datetime_usec
    field :model, :string
    field :scaling_enabled, :boolean, default: false
    field :updated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @fields [
    :api_key,
    :api_key_last4,
    :key_status,
    :key_checked_at,
    :model,
    :scaling_enabled,
    :updated_by_id
  ]

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, @fields)
    |> validate_inclusion(:key_status, ~w(unknown valid rejected))
    |> validate_length(:model, min: 3, max: 80)
    |> check_constraint(:model, name: :organization_ai_settings_values_check)
    |> unique_constraint(:organization_id)
  end
end
