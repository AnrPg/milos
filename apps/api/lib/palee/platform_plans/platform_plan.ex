defmodule Palee.PlatformPlans.PlatformPlan do
  @moduledoc "A plan of the platform's SaaS catalog (ADR-170), edited in the platform console."

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.PlatformPlans.Domain.PlanLimits

  @audiences ~w(gym coach)
  @price_statuses ~w(placeholder confirmed)
  @editable [
    :name,
    :description,
    :limits,
    :monthly_price_cents,
    :annual_price_cents,
    :currency,
    :price_status,
    :trial_days,
    :is_default,
    :public,
    :active,
    :position
  ]

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "platform_plans" do
    field :code, :string
    field :audience, :string
    field :name, :string
    field :description, :string
    field :limits, :map, default: %{}
    field :monthly_price_cents, :integer
    field :annual_price_cents, :integer
    field :currency, :string, default: "EUR"
    field :price_status, :string, default: "placeholder"
    field :trial_days, :integer, default: 0
    field :is_default, :boolean, default: false
    field :public, :boolean, default: true
    field :active, :boolean, default: true
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  @type t :: %__MODULE__{}

  def audiences, do: @audiences
  def price_statuses, do: @price_statuses

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:code, :audience | @editable])
    |> validate_required([:code, :audience])
    |> validate_format(:code, ~r/^[a-z][a-z0-9_]{1,39}$/)
    |> validate_inclusion(:audience, @audiences)
    |> common()
  end

  @doc "The code and audience are fixed once created; subscriptions point at the code."
  def update_changeset(plan, attrs), do: plan |> cast(attrs, @editable) |> common()

  defp common(changeset) do
    changeset
    |> update_change(:name, &String.trim/1)
    |> update_change(:description, &blank_to_nil/1)
    |> update_change(:currency, &String.upcase/1)
    |> validate_required([:name, :currency, :price_status, :trial_days])
    |> validate_length(:name, min: 1, max: 80)
    |> validate_length(:description, max: 500)
    |> validate_format(:currency, ~r/^[A-Z]{3}$/)
    |> validate_inclusion(:price_status, @price_statuses)
    |> validate_number(:monthly_price_cents, greater_than_or_equal_to: 0)
    |> validate_number(:annual_price_cents, greater_than_or_equal_to: 0)
    |> validate_number(:trial_days, greater_than_or_equal_to: 0, less_than_or_equal_to: 365)
    |> validate_limits()
    |> validate_default_is_active()
    |> unique_constraint(:code)
    |> unique_constraint(:is_default, name: :platform_plans_one_default_per_audience_index)
    |> foreign_key_constraint(:code, name: :organization_platform_subscriptions_plan_code_fkey)
  end

  defp validate_limits(changeset) do
    case PlanLimits.parse(get_field(changeset, :limits) || %{}) do
      {:ok, limits} ->
        put_change(changeset, :limits, limits)

      {:error, _reason} ->
        add_error(changeset, :limits, "unknown limit or not a positive integer")
    end
  end

  defp validate_default_is_active(changeset) do
    if get_field(changeset, :is_default) and not get_field(changeset, :active),
      do: add_error(changeset, :active, "a default plan must stay active"),
      else: changeset
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
