defmodule Palee.Finance.Domain.PaymentModelPolicy do
  @moduledoc """
  Pure rules for add-ons, shared and corporate memberships (ADR-098).
  """

  @base_types ~w[membership shared corporate]

  @doc """
  The subscription an add-on attaches to: the first held base (not itself an
  add-on) allowed by the add-on's compatible packages (`"all"` means any
  membership-type base). `requested_id` pins a specific base.
  """
  def add_on_base(subscriptions, compatible, requested_id \\ nil) do
    subscriptions
    |> Enum.filter(&base?(&1, compatible))
    |> Enum.find(&(is_nil(requested_id) or &1.id == requested_id))
    |> case do
      nil -> {:error, :add_on_base_required}
      base -> {:ok, base}
    end
  end

  defp base?(subscription, compatible) do
    is_nil(subscription.base_subscription_id) and package_type(subscription) in @base_types and
      (compatible == "all" or subscription.membership_package_id in List.wrap(compatible))
  end

  def package_type(%{params_snapshot: %{"package_type" => type}}), do: type
  def package_type(_subscription), do: "membership"

  @doc "Add-ons count only while their base subscription is usable."
  def drop_orphan_add_ons(subscriptions) do
    ids = MapSet.new(subscriptions, & &1.id)

    Enum.filter(subscriptions, fn subscription ->
      is_nil(subscription.base_subscription_id) or
        MapSet.member?(ids, subscription.base_subscription_id)
    end)
  end

  @doc "`beneficiaries` counts everyone on the subscription, the payer included."
  def can_add_beneficiary?(terms, active_count, is_minor) do
    total = terms[:beneficiaries] || 1

    cond do
      active_count + 2 > total ->
        {:error, :beneficiary_limit_reached}

      is_minor == true and terms[:allow_minor_beneficiaries] != true ->
        {:error, :minor_beneficiaries_not_allowed}

      true ->
        :ok
    end
  end

  @doc "With per-person quotas each person has the full allowance; shared quotas are pooled."
  def per_person_usage?(%{package_type: "shared", terms: terms}),
    do: (terms[:quota_sharing] || "per_person") == "per_person"

  def per_person_usage?(_plan), do: false

  def seat_available?(seats, active_seats) when is_integer(seats), do: active_seats < seats
  def seat_available?(_seats, _active_seats), do: true

  @doc "Whether an account email belongs to the client's enrollment domain."
  def email_in_domain?(email, domain) when is_binary(email) and is_binary(domain) do
    case String.split(String.downcase(email), "@") do
      [_local, email_domain] ->
        email_domain == domain |> String.trim() |> String.trim_leading("@") |> String.downcase()

      _other ->
        false
    end
  end

  def email_in_domain?(_email, _domain), do: false

  @doc "Inclusive billing period containing `date` for a corporate package."
  def corporate_period(billing_period, %Date{} = date) do
    months =
      case billing_period do
        "quarterly" -> 3
        "semiannual" -> 6
        "annual" -> 12
        _monthly -> 1
      end

    first_month = div(date.month - 1, months) * months + 1
    starts_on = Date.new!(date.year, first_month, 1)
    {starts_on, starts_on |> Date.shift(month: months) |> Date.add(-1)}
  end

  @doc "Agreed billing charges every seat; used billing charges seats held in the period."
  def seats_billed("used", _seats, used), do: used
  def seats_billed(_agreed, seats, _used) when is_integer(seats), do: seats
  def seats_billed(_agreed, _seats, used), do: used
end
