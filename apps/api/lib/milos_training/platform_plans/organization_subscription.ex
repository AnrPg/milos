defmodule MilosTraining.PlatformPlans.OrganizationSubscription do
  @moduledoc "The platform plan an organization is on (ADR-170). Written by vendors only."

  use Ecto.Schema
  import Ecto.Changeset

  alias MilosTraining.PlatformPlans.Domain.SubscriptionPolicy
  alias MilosTraining.PlatformPlans.PlatformPlan

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "organization_platform_subscriptions" do
    field :organization_id, :binary_id
    field :status, :string
    field :trial_ends_at, :utc_datetime_usec
    field :price_override_cents, :integer
    field :notes, :string
    field :updated_by_id, :binary_id

    belongs_to :plan, PlatformPlan,
      foreign_key: :plan_code,
      references: :code,
      type: :string

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def assign_changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :organization_id,
      :plan_code,
      :status,
      :trial_ends_at,
      :price_override_cents,
      :notes,
      :updated_by_id
    ])
    |> update_change(:notes, &blank_to_nil/1)
    |> validate_required([:organization_id, :plan_code, :status])
    |> validate_inclusion(:status, SubscriptionPolicy.statuses())
    |> validate_length(:notes, max: 1000)
    |> validate_number(:price_override_cents, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:plan_code)
    |> foreign_key_constraint(:organization_id)
    |> check_constraint(:trial_ends_at,
      name: :organization_platform_subscriptions_trial_check
    )
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
