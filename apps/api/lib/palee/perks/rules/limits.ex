defmodule Palee.Perks.Rules.Limits do
  @moduledoc """
  Caps: `max_claims` overall, `max_per_member` (default 1), and, inside
  each `period` (day | week | month, starting on the local Monday / 1st),
  `max_per_period` for everyone and `max_per_member_per_period`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @periods ~w(day week month)

  @primary_key false
  embedded_schema do
    field :max_claims, :integer
    field :max_per_member, :integer, default: 1
    field :period, :string
    field :max_per_period, :integer
    field :max_per_member_per_period, :integer
  end

  def periods, do: @periods

  def changeset(limits, attrs) do
    limits
    |> cast(attrs, [
      :max_claims,
      :max_per_member,
      :period,
      :max_per_period,
      :max_per_member_per_period
    ])
    |> validate_required([:max_per_member])
    |> validate_number(:max_claims, greater_than: 0, less_than_or_equal_to: 10_000_000)
    |> validate_number(:max_per_member, greater_than: 0, less_than_or_equal_to: 1_000)
    |> validate_number(:max_per_period, greater_than: 0, less_than_or_equal_to: 10_000_000)
    |> validate_number(:max_per_member_per_period, greater_than: 0, less_than_or_equal_to: 1_000)
    |> validate_inclusion(:period, @periods)
    |> validate_period()
  end

  defp validate_period(changeset) do
    period? = not is_nil(get_field(changeset, :period))

    caps? =
      not is_nil(get_field(changeset, :max_per_period)) or
        not is_nil(get_field(changeset, :max_per_member_per_period))

    cond do
      caps? and not period? -> add_error(changeset, :period, "choose day, week or month")
      period? and not caps? -> add_error(changeset, :max_per_period, "set a limit for the period")
      true -> changeset
    end
  end
end
