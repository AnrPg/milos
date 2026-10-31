defmodule Palee.Finance.Domain.PackageRequestPolicy do
  @moduledoc """
  ADR-291: a package a person asked for in the app («Το θέλω») when the box
  takes no online payments, waiting to be paid at the front desk
  («Περιμένει πληρωμή»). Pure rules; the store does the writing.

    * A request is not a subscription: it grants no access and owes nothing.
    * The desk's «Είσπραξη» records the money and assigns the package in
      one step (`activated`).
    * The person can take it back (`cancelled`) while it is pending.
    * It is held for 14 days, counted in the box's own days: from the day
      after `hold_until` it no longer shows and is closed as `lapsed`.
  """

  @hold_days 14
  @statuses ~w(pending activated cancelled lapsed)
  @sources ~w(member staff)
  # Sold only beside another package or through an employer: never asked
  # for alone.
  @needs_more ~w(add_on shared corporate)

  def hold_days, do: @hold_days
  def statuses, do: @statuses
  def sources, do: @sources
  def needs_more, do: @needs_more

  @doc "The last day a request made on `today` (box-local) is held."
  @spec hold_until(Date.t()) :: Date.t()
  def hold_until(%Date{} = today), do: Date.add(today, @hold_days)

  @doc "Whether the request still waits for payment on `today` (box-local)."
  def open?(%{status: "pending", hold_until: %Date{} = until}, %Date{} = today),
    do: Date.compare(today, until) != :gt

  def open?(_request, _today), do: false

  @doc "Days left, including today, for the queue's «σε N ημέρες»."
  def days_left(%{hold_until: %Date{} = until}, %Date{} = today),
    do: max(Date.diff(until, today), 0)

  @doc """
  Whether a package can be asked for at the desk: active, with a price (a
  free package needs no payment), and sold on its own (not an add-on, a
  shared or a corporate package).
  """
  def requestable?(package) when is_map(package) do
    package[:active] == true and is_integer(package[:base_price_cents]) and
      package.base_price_cents > 0 and package[:package_type] not in @needs_more
  end

  def requestable?(_package), do: false
end
