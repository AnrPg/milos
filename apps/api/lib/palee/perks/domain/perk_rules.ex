defmodule Palee.Perks.Domain.PerkRules do
  @moduledoc """
  The rules of a partner perk (ADR-191), pure. A perk carries its current
  version (`perk.version`: `benefit`, `rules`, `redemption`, `terms`).

  Lifecycle: `draft → published ⇄ paused → expired`. A published perk whose
  window has passed reads as `expired` without a write, so lists and claims
  never depend on a sweep. Publishing is a going-live action (demo
  businesses are refused by the caller through `GoLivePolicy`).

  Who may claim: a client of the business at one of the perk's branches (a
  member without a home branch roams, ADR-186), meeting the version's
  eligibility (packages, groups, tenure); when: published, inside the
  window and the recurring windows; how often: overall, per member and per
  period, everyone and each member. Every check answers one stable error.

  Versioning: until the first claim a change amends the current version;
  after it, a change is a new version and claims keep the one they agreed
  to. The method itself can't change once claimed.
  """

  @statuses ~w(draft published paused expired)
  @claim_statuses ~w(claimed used revoked)

  def statuses, do: @statuses
  def claim_statuses, do: @claim_statuses

  # -- lifecycle -------------------------------------------------------------

  @doc "The status a reader sees on `today`: a published perk past its window is expired."
  def effective_status(%{status: "published", valid_until: %Date{} = until}, %Date{} = today) do
    if Date.compare(until, today) == :lt, do: "expired", else: "published"
  end

  def effective_status(%{status: status}, _today), do: status

  @doc "Whether the window holds `today` (open-ended sides always hold)."
  def in_window?(perk, %Date{} = today) do
    starts? = is_nil(perk.valid_from) or Date.compare(perk.valid_from, today) != :gt
    ends? = is_nil(perk.valid_until) or Date.compare(perk.valid_until, today) != :lt
    starts? and ends?
  end

  @doc """
  Whether a local moment is inside the recurring weekly windows (always,
  when there are none).
  """
  def in_recurring?(%{recurring: windows}, %NaiveDateTime{} = local) when is_list(windows) and windows != [] do
    day = local |> NaiveDateTime.to_date() |> Date.day_of_week()
    time = NaiveDateTime.to_time(local)

    Enum.any?(windows, fn window ->
      day in window.weekdays and Time.compare(time, window.starts_at) != :lt and
        Time.compare(time, window.ends_at) == :lt
    end)
  end

  def in_recurring?(_rules, _local), do: true

  @doc "Published, started and not ended: members can see it."
  def live?(perk, today), do: perk.status == "published" and in_window?(perk, today)

  @doc """
  The changes of one lifecycle step (`:publish`, `:pause`, `:expire`) at
  `now` / `today`, or `:perk_transition_invalid` / `:perk_ended`.
  """
  def transition(perk, step, %DateTime{} = now, %Date{} = today) do
    case {step, effective_status(perk, today)} do
      {:publish, status} when status in ["draft", "paused"] ->
        if ended?(perk, today),
          do: {:error, :perk_ended},
          else:
            {:ok,
             %{status: "published", published_at: perk.published_at || now, paused_at: nil}}

      {:pause, "published"} ->
        {:ok, %{status: "paused", paused_at: now}}

      {:expire, status} when status in ["published", "paused"] ->
        {:ok, %{status: "expired", expired_at: now}}

      _other ->
        {:error, :perk_transition_invalid}
    end
  end

  defp ended?(%{valid_until: %Date{} = until}, today), do: Date.compare(until, today) == :lt
  defp ended?(_perk, _today), do: false

  @doc """
  Whether a change may be applied: an ended perk is read-only, the method
  is fixed once claimed, and the overall cap of the new rules can't drop
  below the claims made. `perk_changes` are perk fields; `rules` the new
  version's rules (or nil when unchanged).
  """
  def check_update(perk, perk_changes, rules, today) do
    method = Map.get(perk_changes, :redemption_method, perk.redemption_method)
    cap = rules && rules.limits && rules.limits.max_claims

    cond do
      effective_status(perk, today) == "expired" -> {:error, :perk_read_only}
      perk.claims_count > 0 and method != perk.redemption_method -> {:error, :perk_locked_after_claims}
      is_integer(cap) and cap < perk.claims_count -> {:error, :perk_cap_below_claims}
      true -> :ok
    end
  end

  @doc "`:amend` the current version while nobody claimed, else a `:new` one."
  def version_mode(%{claims_count: 0}), do: :amend
  def version_mode(_perk), do: :new

  # -- who -------------------------------------------------------------------

  @doc """
  Whether the perk is for a member with these facts: `%{package_ids,
  group_ids, home_location_id, joined_on, today}`.
  """
  def for_member?(perk, facts) do
    eligibility = perk.version.rules.eligibility

    branch?(perk, Map.get(facts, :home_location_id)) and
      any_of?(eligibility.package_ids, Map.get(facts, :package_ids, [])) and
      any_of?(eligibility.group_ids, Map.get(facts, :group_ids, [])) and
      tenure?(eligibility.min_tenure_days, Map.get(facts, :joined_on), Map.get(facts, :today))
  end

  defp branch?(%{all_locations: true}, _home), do: true
  defp branch?(_perk, nil), do: true
  defp branch?(%{location_ids: ids}, home), do: home in ids

  defp any_of?([], _held), do: true
  defp any_of?(wanted, held), do: Enum.any?(wanted, &(&1 in held))

  defp tenure?(nil, _joined, _today), do: true
  defp tenure?(_days, nil, _today), do: false

  defp tenure?(days, %Date{} = joined, %Date{} = today),
    do: Date.diff(today, joined) >= days

  # -- how often -------------------------------------------------------------

  @doc """
  Where the current period starts, as a local time, for the version's
  period limits (`nil` without one): the day's midnight, Monday's or the
  1st of the month's.
  """
  def period_start(%{limits: %{period: period}}, %NaiveDateTime{} = local) when is_binary(period) do
    date = NaiveDateTime.to_date(local)

    start =
      case period do
        "day" -> date
        "week" -> Date.add(date, 1 - Date.day_of_week(date))
        "month" -> Date.beginning_of_month(date)
      end

    NaiveDateTime.new!(start, ~T[00:00:00])
  end

  def period_start(_rules, _local), do: nil

  @doc """
  Whether a member may make a new claim, decided under the perk's lock.
  `facts`: `%{today, local_now, member_claims, period}` where `period` is
  `%{member: n, all: n}` (claims that count since the period started) or
  nil. `:ok` or `{:error, reason}`.
  """
  def claim_check(perk, facts) do
    limits = perk.version.rules.limits
    period = Map.get(facts, :period) || %{member: 0, all: 0}

    cond do
      perk.status != "published" or not in_window?(perk, facts.today) ->
        {:error, :perk_not_available}

      not in_recurring?(perk.version.rules, facts.local_now) ->
        {:error, :perk_outside_hours}

      over?(limits.max_claims, perk.claims_count) ->
        {:error, :perk_sold_out}

      over?(limits.max_per_period, period.all) ->
        {:error, :perk_period_sold_out}

      over?(limits.max_per_member, facts.member_claims) ->
        {:error, :perk_member_limit}

      over?(limits.max_per_member_per_period, period.member) ->
        {:error, :perk_member_period_limit}

      true ->
        :ok
    end
  end

  defp over?(nil, _count), do: false
  defp over?(cap, count), do: count >= cap

  @doc """
  Why a claim can't be used now, or `:ok`: unused, the perk published or
  paused (pausing stops new claims only), inside its window and recurring
  windows. `rules` are the claim's own version's.
  """
  def usable(perk, rules, claim, today, local_now) do
    cond do
      claim.status == "used" -> {:error, :perk_claim_already_used}
      claim.status == "revoked" -> {:error, :perk_claim_not_open}
      perk.status not in ["published", "paused"] or not in_window?(perk, today) -> {:error, :perk_not_available}
      not in_recurring?(rules, local_now) -> {:error, :perk_outside_hours}
      true -> :ok
    end
  end

  def usable?(perk, rules, claim, today, local_now),
    do: usable(perk, rules, claim, today, local_now) == :ok

  @doc "Claims left under the overall cap, nil when uncapped."
  def remaining(%{version: %{rules: %{limits: %{max_claims: cap}}}, claims_count: count})
      when is_integer(cap),
      do: max(cap - count, 0)

  def remaining(_perk), do: nil

  # -- reading ---------------------------------------------------------------

  @doc """
  The benefit in one short line, the shape the billing card shows:
  `10%`, `5.00 EUR`, `Δωρεάν: shaker`-like neutral English (`Free shaker`),
  `Buy 2 get 1`, or the free text. Clients translate from the fields.
  """
  def benefit_label(%{type: "percent", percent: value}), do: "#{value}%"
  def benefit_label(%{type: "fixed_amount", amount_cents: cents, currency: currency}), do: money(cents, currency)
  def benefit_label(%{type: "free_item", item: item}), do: "Free #{item}"

  def benefit_label(%{type: "buy_x_get_y", buy_quantity: buy, get_quantity: get} = benefit),
    do: "Buy #{buy} get #{get}" <> if(benefit.item, do: " #{benefit.item}", else: "")

  def benefit_label(%{text: text}), do: text

  @doc "Cents as `12.50 EUR`."
  def money(cents, currency) do
    whole = div(cents, 100)
    fraction = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{whole}.#{fraction} #{currency}"
  end
end
