defmodule Palee.Finance.Domain.SubscriptionTerms do
  @moduledoc """
  Pure rules for Phase B commercial terms (ADR-097): minimum commitment,
  freezes, activation on first use, rollover and member discounts.
  """

  alias Palee.Finance.Domain.PackageCatalog

  @discount_categories %{
    "products" => "product",
    "personal_training" => "personal_training",
    "events" => "event"
  }

  @doc "Inclusive last day of a minimum commitment, or nil when there is none."
  def commitment_ends_on(_starts_on, months) when months in [nil, 0], do: nil

  def commitment_ends_on(%Date{} = starts_on, months) when is_integer(months) and months > 0,
    do: starts_on |> Date.shift(month: months) |> Date.add(-1)

  @doc "Cancelling before the commitment ends needs an explicit override reason."
  def cancellation_allowed?(nil, _today, _override_reason), do: :ok

  def cancellation_allowed?(%Date{} = commitment_ends_on, %Date{} = today, override_reason) do
    cond do
      Date.compare(today, commitment_ends_on) == :gt -> :ok
      is_binary(override_reason) and String.trim(override_reason) != "" -> :ok
      true -> {:error, :package_commitment_active}
    end
  end

  @doc "End date for a subscription activated on first use."
  def activation_ends_on(%Date{} = activated_on, validity) when is_map(validity),
    do: PackageCatalog.duration_end(activated_on, validity)

  def activation_ends_on(_activated_on, _validity), do: nil

  @doc "Length of an inclusive date range in days."
  def days(%Date{} = starts_on, %Date{} = ends_on), do: Date.diff(ends_on, starts_on) + 1

  @doc """
  Validates a freeze request against the yearly allowance. `used` holds the
  `{starts_on, ends_on}` ranges of existing, not cancelled freezes.
  """
  def validate_freeze(%Date{} = starts_on, %Date{} = ends_on, per_year, used, %Date{} = today) do
    requested = days(starts_on, ends_on)
    year_used = used_days_in_year(used, starts_on.year)

    cond do
      Date.compare(ends_on, starts_on) == :lt -> {:error, :invalid_freeze_dates}
      Date.compare(starts_on, today) == :lt -> {:error, :freeze_in_past}
      per_year in [nil, 0] -> {:error, :freeze_not_included}
      overlaps?(used, starts_on, ends_on) -> {:error, :freeze_overlaps}
      year_used + requested > per_year -> {:error, :freeze_allowance_exceeded}
      true -> {:ok, %{days: requested, remaining: per_year - year_used - requested}}
    end
  end

  def used_days_in_year(used, year) do
    Enum.reduce(used, 0, fn {starts_on, ends_on}, acc ->
      first = Enum.max([starts_on, Date.new!(year, 1, 1)], Date)
      last = Enum.min([ends_on, Date.new!(year, 12, 31)], Date)
      if Date.compare(last, first) == :lt, do: acc, else: acc + days(first, last)
    end)
  end

  def frozen_on?(freezes, %Date{} = date) do
    Enum.any?(freezes, fn {starts_on, ends_on} ->
      Date.compare(date, starts_on) != :lt and Date.compare(date, ends_on) != :gt
    end)
  end

  defp overlaps?(used, starts_on, ends_on) do
    Enum.any?(used, fn {other_start, other_end} ->
      Date.compare(starts_on, other_end) != :gt and Date.compare(other_start, ends_on) != :gt
    end)
  end

  @doc "Units carried over from the previous period, capped by the package rollover."
  def carry_over(_limit, _extensions, _committed, rollover_max) when rollover_max in [nil, 0],
    do: 0

  def carry_over(:unlimited, _extensions, _committed, _rollover_max), do: 0
  def carry_over(nil, _extensions, _committed, _rollover_max), do: 0

  def carry_over(limit, extensions, committed, rollover_max)
      when is_integer(limit) and is_integer(rollover_max) do
    (limit + extensions - committed)
    |> max(0)
    |> min(rollover_max)
  end

  @doc """
  Applies the member discount to manual charges whose category is in the
  member's discount scope by raising each line's own discount. Other lines are
  returned unchanged.
  """
  def apply_member_discount(lines, percent, _scope) when percent in [nil, 0], do: lines

  def apply_member_discount(lines, percent, scope) when is_integer(percent) do
    categories = scope |> Enum.map(&Map.get(@discount_categories, &1)) |> Enum.reject(&is_nil/1)

    Enum.map(lines, fn line ->
      if line["line_type"] == "manual_charge" and line["charge_category"] in categories do
        subtotal = (line["quantity"] || 1) * (line["unit_amount_cents"] || 0)
        existing = line["discount_cents"] || 0
        member = div(max(subtotal - existing, 0) * percent, 100)

        line
        |> Map.put("discount_cents", existing + member)
        |> Map.put("member_discount_percent", percent)
      else
        line
      end
    end)
  end
end
