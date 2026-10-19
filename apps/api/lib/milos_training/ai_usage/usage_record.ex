defmodule MilosTraining.AiUsage.UsageRecord do
  @moduledoc "One billed model call (ADR-152). Append-only."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ai_usage_records" do
    field :organization_id, :binary_id
    field :user_id, :binary_id
    field :operation_id, :binary_id
    field :feature, :string
    field :agent, :string
    field :provider, :string
    field :model, :string
    field :model_version, :string
    field :input_tokens, :integer, default: 0
    field :cached_input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :thinking_tokens, :integer, default: 0
    field :cost_nano_usd, :integer
    field :duration_ms, :integer
    field :occurred_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @fields [
    :user_id,
    :operation_id,
    :feature,
    :agent,
    :provider,
    :model,
    :model_version,
    :input_tokens,
    :cached_input_tokens,
    :output_tokens,
    :thinking_tokens,
    :cost_nano_usd,
    :duration_ms,
    :occurred_at
  ]

  @token_fields [:input_tokens, :cached_input_tokens, :output_tokens, :thinking_tokens]

  def changeset(organization_id, params) do
    %__MODULE__{organization_id: organization_id}
    |> cast(params, @fields)
    |> validate_required([
      :operation_id,
      :feature,
      :provider,
      :model,
      :occurred_at | @token_fields
    ])
    |> validate_length(:feature, max: 64)
    |> validate_length(:agent, max: 64)
    |> validate_length(:provider, max: 32)
    |> validate_length(:model, max: 128)
    |> validate_length(:model_version, max: 128)
    |> then(fn changeset ->
      Enum.reduce(@token_fields, changeset, &validate_number(&2, &1, greater_than_or_equal_to: 0))
    end)
    |> validate_number(:cost_nano_usd, greater_than_or_equal_to: 0)
    |> validate_number(:duration_ms, greater_than_or_equal_to: 0)
    |> check_constraint(:input_tokens, name: :ai_usage_records_tokens_check)
    |> check_constraint(:cost_nano_usd, name: :ai_usage_records_cost_check)
  end
end
