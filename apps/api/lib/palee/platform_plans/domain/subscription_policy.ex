defmodule Palee.PlatformPlans.Domain.SubscriptionPolicy do
  @moduledoc """
  An organization's platform subscription (ADR-170). There is no card
  processor yet: a vendor records what was agreed, and nothing here ever
  locks a gym or a coach out. A trial that ended, a late payment or a
  cancellation only produce a notice for the organization's owner and admins
  and a flag in the platform console.
  """

  @statuses ~w(trialing active past_due cancelled comped)
  @trial_warning_days 7

  def statuses, do: @statuses

  @doc "The status as of `now`: a trial past its end reads `trial_expired`."
  def effective_status(
        %{status: "trialing", trial_ends_at: %DateTime{} = ends},
        %DateTime{} = now
      ) do
    if DateTime.compare(ends, now) == :gt, do: "trialing", else: "trial_expired"
  end

  def effective_status(%{status: status}, _now), do: status

  @doc "Whole days left of a running trial, or nil."
  def trial_days_left(%{status: "trialing", trial_ends_at: %DateTime{} = ends}, %DateTime{} = now) do
    seconds = DateTime.diff(ends, now)
    if seconds > 0, do: div(seconds + 86_399, 86_400), else: nil
  end

  def trial_days_left(_subscription, _now), do: nil

  @doc """
  The one notice the owner sees on the plan card, if any:
  `trial_ending` (last #{@trial_warning_days} days), `trial_expired`,
  `past_due` or `cancelled`.
  """
  def notice(subscription, now) do
    case effective_status(subscription, now) do
      "trialing" ->
        if (trial_days_left(subscription, now) || 0) <= @trial_warning_days,
          do: "trial_ending",
          else: nil

      status when status in ~w(trial_expired past_due cancelled) ->
        status

      _ok ->
        nil
    end
  end

  @doc """
  Validates a vendor's assignment. A trial needs its end; any other status
  clears it. `price_override_cents` is a negotiated price (nil = list price).
  """
  def validate_assignment(attrs, now) when is_map(attrs) do
    status = value(attrs, :status)
    trial_ends_at = value(attrs, :trial_ends_at)
    override = value(attrs, :price_override_cents)

    cond do
      status not in @statuses ->
        {:error, :invalid_subscription_status}

      status == "trialing" and not match?(%DateTime{}, trial_ends_at) ->
        {:error, :trial_end_required}

      status == "trialing" and DateTime.compare(trial_ends_at, now) != :gt ->
        {:error, :trial_end_required}

      not (is_nil(override) or (is_integer(override) and override >= 0)) ->
        {:error, :invalid_price}

      true ->
        {:ok,
         %{
           status: status,
           trial_ends_at: if(status == "trialing", do: trial_ends_at),
           price_override_cents: override
         }}
    end
  end

  defp value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
end
