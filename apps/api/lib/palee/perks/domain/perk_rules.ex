defmodule Palee.Perks.Domain.PerkRules do
  @moduledoc """
  The rules of a partner perk (ADR-191), pure: its lifecycle, who it is for,
  when a member may claim it, and how its benefit reads.

  Lifecycle: `draft → published ⇄ paused → expired`. A published perk whose
  `valid_until` has passed reads as `expired` without a write, so lists and
  claims never depend on a sweep. Publishing is a going-live action (demo
  businesses are refused by the caller through `GoLivePolicy`).

  Audience: every client of the business, or the holders of a current
  package among `package_ids`; branches (`all_locations` / `location_ids`)
  narrow it further to members whose home branch is one of them. A member
  without a home branch roams (ADR-186: members are not branch scoped), so
  they see branch-limited perks too.
  """

  @benefit_types ~w(percent fixed_amount free_text)
  @methods ~w(shared_code unique_code qr)
  @statuses ~w(draft published paused expired)
  @audiences ~w(all_clients packages)
  @claim_statuses ~w(claimed used revoked)

  # Fields whose meaning a member who already claimed relies on: once there
  # are claims they stay as they were (a new perk is the way to change them).
  @locked_after_claims ~w(redemption_method shared_code benefit_type benefit_value benefit_text currency)a

  def benefit_types, do: @benefit_types
  def methods, do: @methods
  def statuses, do: @statuses
  def audiences, do: @audiences
  def claim_statuses, do: @claim_statuses
  def locked_after_claims, do: @locked_after_claims

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

  @doc "Published, started and not ended: members can see and claim it."
  def live?(perk, today), do: perk.status == "published" and in_window?(perk, today)

  @doc """
  The changes of one lifecycle step (`:publish`, `:pause`, `:expire`) at
  `now` / `today`, or an error: `:perk_transition_invalid` for a step the
  status doesn't allow, `:perk_ended` for publishing past the window.
  """
  def transition(perk, step, %DateTime{} = now, %Date{} = today) do
    status = effective_status(perk, today)

    case {step, status} do
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
  Whether `changes` (atom keys) may be applied to a perk: an expired perk is
  read-only, fields members rely on are locked once claimed, and the overall
  cap can't drop below the claims already made.
  """
  def check_update(perk, changes, today) do
    cond do
      effective_status(perk, today) == "expired" ->
        {:error, :perk_read_only}

      perk.claims_count > 0 and locked_change?(perk, changes) ->
        {:error, :perk_locked_after_claims}

      cap_below_claims?(perk, changes) ->
        {:error, :perk_cap_below_claims}

      true ->
        :ok
    end
  end

  defp locked_change?(perk, changes) do
    Enum.any?(@locked_after_claims, fn field ->
      Map.has_key?(changes, field) and Map.get(changes, field) != Map.get(perk, field)
    end)
  end

  defp cap_below_claims?(perk, %{max_claims: cap}) when is_integer(cap),
    do: cap < perk.claims_count

  defp cap_below_claims?(_perk, _changes), do: false

  @doc """
  Whether the perk is for a member with these facts:
  `%{package_ids: [id], home_location_id: id | nil}`.
  """
  def for_member?(perk, facts) do
    audience?(perk, Map.get(facts, :package_ids, [])) and
      branch?(perk, Map.get(facts, :home_location_id))
  end

  defp audience?(%{audience: "packages", package_ids: wanted}, held),
    do: Enum.any?(wanted, &(&1 in held))

  defp audience?(_perk, _held), do: true

  defp branch?(%{all_locations: true}, _home), do: true
  defp branch?(_perk, nil), do: true
  defp branch?(%{location_ids: ids}, home), do: home in ids

  @doc """
  Whether a member may make a new claim, decided under the perk's lock:
  `facts` are `%{today, member_claims}` (the member's claims that count:
  not revoked). `:ok` or `{:error, reason}`.
  """
  def claim_check(perk, %{today: today, member_claims: member_claims}) do
    cond do
      perk.status != "published" or not in_window?(perk, today) -> {:error, :perk_not_available}
      is_integer(perk.max_claims) and perk.claims_count >= perk.max_claims -> {:error, :perk_sold_out}
      member_claims >= perk.max_claims_per_member -> {:error, :perk_member_limit}
      true -> :ok
    end
  end

  @doc "Whether a claim can still be used at the partner on `today`."
  def usable?(perk, claim, today),
    do: claim.status == "claimed" and perk.status in ["published", "paused"] and in_window?(perk, today)

  @doc "Claims and uses left under the overall cap, nil when uncapped."
  def remaining(%{max_claims: nil}), do: nil
  def remaining(%{max_claims: cap, claims_count: count}), do: max(cap - count, 0)

  @doc """
  The benefit in one short line, the shape the billing card shows:
  `10%`, `5.00 EUR` or the free text.
  """
  def benefit_label(%{benefit_type: "percent", benefit_value: value}), do: "#{value}%"

  def benefit_label(%{benefit_type: "fixed_amount", benefit_value: cents, currency: currency}) do
    whole = div(cents, 100)
    fraction = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{whole}.#{fraction} #{currency}"
  end

  def benefit_label(%{benefit_text: text}), do: text
end
