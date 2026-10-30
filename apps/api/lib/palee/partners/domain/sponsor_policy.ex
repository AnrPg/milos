defmodule Palee.Partners.Domain.SponsorPolicy do
  @moduledoc """
  Sponsors of the second verification path (ADR-280 §2).

  - Two vouches are needed (`required/0`).
  - Only a person verified through a membership, not suspended, may vouch,
    never for themselves and never across a block either way.
  - At most 5 vouches per sponsor in any 30 days (rolling).
  - When someone a sponsor vouched for is suspended, the sponsor cannot
    vouch for 60 days (their own access stays).
  - A sponsor link is single use and lives 10 minutes; only its SHA-256
    digest is stored.
  """

  @required 2
  @quota 5
  @quota_days 30
  @penalty_days 60
  @link_minutes 10
  @channels ~w(buddy link)
  @statuses ~w(requested vouched declined cancelled)
  @decisions ~w(vouch decline)

  def required, do: @required
  def quota, do: @quota
  def quota_days, do: @quota_days
  def penalty_days, do: @penalty_days
  def link_minutes, do: @link_minutes
  def channels, do: @channels
  def statuses, do: @statuses
  def decisions, do: @decisions

  @doc "Start of the rolling window the vouch quota counts in."
  def quota_window_start(%DateTime{} = now), do: DateTime.add(now, -@quota_days * 86_400)

  @doc "Until when a sponsor of a suspended person may not vouch."
  def penalty_until(%DateTime{} = now), do: DateTime.add(now, @penalty_days * 86_400)

  @doc "The later of an existing penalty and a new one."
  def extend_penalty(nil, %DateTime{} = until), do: until

  def extend_penalty(%DateTime{} = current, %DateTime{} = until),
    do: if(DateTime.compare(current, until) == :gt, do: current, else: until)

  @doc "Vouches left in the window."
  def quota_left(vouches) when is_integer(vouches), do: max(@quota - vouches, 0)

  @doc "Vouches a candidate holds."
  def vouch_count(sponsorships), do: Enum.count(sponsorships, &(&1.status == "vouched"))

  @doc "Whether the candidate has enough vouches."
  def enough?(vouches) when is_integer(vouches), do: vouches >= @required

  @doc """
  Whether `standing` (a sponsor's verification: `method`, `status`,
  `penalty_until`, and `vouches` in the window) allows vouching for
  `candidate_id` now. `blocked?` says whether either blocked the other.
  """
  @spec check(map() | nil, Ecto.UUID.t(), Ecto.UUID.t(), boolean(), DateTime.t()) ::
          :ok
          | {:error,
             :partner_sponsor_not_eligible | :partner_sponsor_quota | :partner_sponsor_penalty}
  def check(standing, sponsor_id, candidate_id, blocked?, %DateTime{} = now) do
    case reason(standing, sponsor_id, candidate_id, blocked?, now) do
      nil -> :ok
      :not_verified -> {:error, :partner_sponsor_not_eligible}
      :blocked -> {:error, :partner_sponsor_not_eligible}
      :self -> {:error, :partner_sponsor_not_eligible}
      :quota -> {:error, :partner_sponsor_quota}
      :penalty -> {:error, :partner_sponsor_penalty}
    end
  end

  @doc "Why a person may not vouch (nil when they may)."
  def reason(standing, sponsor_id, candidate_id, blocked?, %DateTime{} = now) do
    cond do
      sponsor_id == candidate_id -> :self
      not membership_verified?(standing) -> :not_verified
      blocked? -> :blocked
      penalized?(standing, now) -> :penalty
      quota_left(Map.get(standing, :vouches) || 0) == 0 -> :quota
      true -> nil
    end
  end

  @doc "Verified through a membership and not suspended."
  def membership_verified?(%{method: "membership", status: "verified"}), do: true
  def membership_verified?(_standing), do: false

  @doc "Whether a penalty is running at `now`."
  def penalized?(standing, %DateTime{} = now) do
    case standing && Map.get(standing, :penalty_until) do
      %DateTime{} = until -> DateTime.compare(until, now) == :gt
      _none -> false
    end
  end

  @doc "`{:ok, \"vouch\" | \"decline\"}` from the request body's `decision`."
  def normalize_decision(decision) when decision in @decisions, do: {:ok, decision}
  def normalize_decision(_decision), do: {:error, :invalid_partner_vouch_decision}

  @doc "The changes a sponsor's answer makes to a requested sponsorship."
  def answer(%{status: "requested"}, decision, %DateTime{} = now),
    do: {:ok, %{status: answered(decision), decided_at: now}}

  def answer(_sponsorship, _decision, _now), do: {:error, :partner_vouch_request_closed}

  defp answered("vouch"), do: "vouched"
  defp answered("decline"), do: "declined"

  @doc """
  What asking a sponsor does given the pair's existing sponsorship:
  `:insert`, `{:update, changes}` (asking again after a cancel) or
  `{:keep, sponsorship}` (already asked or vouched).
  """
  def ask(nil, _now), do: :insert
  def ask(%{status: "cancelled"}, now), do: {:update, %{status: "requested", requested_at: now}}

  def ask(%{status: status} = sponsorship, _now) when status in ["requested", "vouched"],
    do: {:keep, sponsorship}

  def ask(%{status: "declined"}, _now), do: {:error, :partner_sponsor_declined}

  @doc "The candidate withdraws a request still waiting for an answer."
  def cancel(%{status: "requested"}), do: {:ok, %{status: "cancelled"}}
  def cancel(_sponsorship), do: {:error, :not_found}

  # -- links ------------------------------------------------------------------

  @doc "When a link made at `now` expires."
  def link_expires_at(%DateTime{} = now), do: DateTime.add(now, @link_minutes * 60)

  @doc "The stored digest of a link token."
  def link_digest(token) when is_binary(token), do: :crypto.hash(:sha256, token)

  @doc "A token as typed or scanned: `{:ok, token}` or the expired error."
  def normalize_token(token) when is_binary(token) do
    token = String.trim(token)

    if byte_size(token) in 16..128 and token =~ ~r/^[A-Za-z0-9_-]+$/,
      do: {:ok, token},
      else: {:error, :partner_link_expired}
  end

  def normalize_token(_token), do: {:error, :partner_link_expired}

  @doc "A link may be used once, before it expires, and not by its candidate."
  def check_link(nil, _sponsor_id, _now), do: {:error, :partner_link_expired}

  def check_link(%{candidate_id: candidate_id}, candidate_id, _now),
    do: {:error, :partner_sponsor_not_eligible}

  def check_link(%{used_at: %DateTime{}}, _sponsor_id, _now), do: {:error, :partner_link_expired}

  def check_link(%{expires_at: %DateTime{} = expires_at}, _sponsor_id, %DateTime{} = now) do
    if DateTime.compare(expires_at, now) == :gt, do: :ok, else: {:error, :partner_link_expired}
  end

  def check_link(_link, _sponsor_id, _now), do: {:error, :partner_link_expired}
end
