defmodule Palee.Application.PartnerSponsoring do
  @moduledoc """
  The sponsor's side of Partners verification (ADR-280 §2, §5): requests to
  vouch from Buddies (`vouch_requests/1`, `decide/4`), a candidate's link
  (`inspect_link/3`, `vouch_by_link/3`) and the sponsor's own quota and
  pause (`vouching/2`).

  Only a person verified through a membership, not suspended, not paused
  and within 5 vouches in 30 days may vouch, never for themselves and never
  across a block. A vouch tells the candidate.
  """

  alias Palee.Application.{CommunityPeople, PartnerEligibility, PartnerVerificationNotices}
  alias Palee.Community
  alias Palee.Partners.Verifications

  @doc "Requests waiting for the sponsor's answer, newest first."
  def vouch_requests(%{user_id: user_id} = context, now \\ DateTime.utc_now()) do
    scope = scope(context)
    blocked = MapSet.new(Community.blocked_user_ids(context))

    requests =
      scope
      |> Verifications.sponsorships_of_sponsor(user_id, ["requested"])
      |> Enum.reject(&MapSet.member?(blocked, &1.candidate_id))

    people = CommunityPeople.by_ids(Enum.map(requests, & &1.candidate_id))

    with {:ok, quota} <- vouching(context, now) do
      {:ok,
       %{
         requests:
           Enum.map(requests, fn sponsorship ->
             %{
               id: sponsorship.id,
               person: CommunityPeople.person(people, sponsorship.candidate_id),
               requested_at: sponsorship.requested_at
             }
           end),
         vouching: quota
       }}
    end
  end

  @doc "Vouches for or declines a candidate who asked (`decision`)."
  def decide(%{user_id: user_id} = context, sponsorship_id, params, now \\ DateTime.utc_now()) do
    scope = scope(context)

    with {:ok, decision} <- Verifications.normalize_vouch_decision(param(params, :decision)),
         %{sponsor_id: ^user_id} = sponsorship <-
           Verifications.get_sponsorship(scope, sponsorship_id) || {:error, :not_found},
         :ok <- may_vouch(context, decision, sponsorship.candidate_id, now),
         {:ok, changes} <- Verifications.answer_sponsorship(sponsorship, decision, now),
         {:ok, answered} <- Verifications.update_sponsorship(scope, sponsorship, changes) do
      if answered.status == "vouched", do: PartnerVerificationNotices.vouched(answered)
      {:ok, %{id: answered.id, status: answered.status, decided_at: answered.decided_at}}
    else
      %{} -> {:error, :not_found}
      error -> error
    end
  end

  # Declining needs no standing; vouching does.
  defp may_vouch(_context, "decline", _candidate_id, _now), do: :ok
  defp may_vouch(context, "vouch", candidate_id, now), do: check(context, candidate_id, now)

  @doc "What a sponsor sees on opening a candidate's link (`token`)."
  def inspect_link(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    scope = scope(context)

    with {:ok, token} <- Verifications.normalize_link_token(param(params, :token)),
         link = Verifications.find_link(scope, Verifications.link_digest(token)),
         :ok <- Verifications.check_link(link, user_id, now) do
      reason =
        case check(context, link.candidate_id, now) do
          :ok -> nil
          {:error, reason} -> Atom.to_string(reason)
        end

      people = CommunityPeople.by_ids([link.candidate_id])

      {:ok,
       %{
         person: CommunityPeople.person(people, link.candidate_id),
         expires_at: link.expires_at,
         can_vouch: is_nil(reason),
         reason: reason
       }}
    end
  end

  @doc "Vouches through a candidate's link (`token`); the link is used up."
  def vouch_by_link(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    scope = scope(context)

    with {:ok, token} <- Verifications.normalize_link_token(param(params, :token)),
         digest = Verifications.link_digest(token),
         link = Verifications.find_link(scope, digest),
         :ok <- Verifications.check_link(link, user_id, now),
         :ok <- check(context, link.candidate_id, now),
         {:ok, sponsorship} <-
           Verifications.transaction(scope, fn -> redeem(scope, digest, user_id, now) end) do
      PartnerVerificationNotices.vouched(sponsorship)
      {:ok, %{id: sponsorship.id, status: sponsorship.status, decided_at: sponsorship.decided_at}}
    end
  end

  defp redeem(scope, digest, user_id, now) do
    case Verifications.redeem_link(scope, digest, now) do
      nil ->
        {:error, :partner_link_expired}

      candidate_id ->
        case Verifications.sponsorship_between(scope, candidate_id, user_id) do
          nil ->
            Verifications.insert_sponsorship(scope, %{
              candidate_id: candidate_id,
              sponsor_id: user_id,
              channel: "link",
              status: "vouched",
              requested_at: now,
              decided_at: now
            })

          %{status: "vouched"} = sponsorship ->
            {:ok, sponsorship}

          sponsorship ->
            Verifications.update_sponsorship(scope, sponsorship, %{
              status: "vouched",
              decided_at: now
            })
        end
    end
  end

  @doc "The sponsor's own standing: may they vouch, how many vouches are left, any pause."
  def vouching(%{user_id: user_id} = context, now \\ DateTime.utc_now()) do
    scope = scope(context)
    standing = standing(scope, user_id, now)
    reason = Verifications.sponsor_reason(standing, user_id, nil, false, now)
    used = (standing && standing.vouches) || 0

    {:ok,
     %{
       can_vouch: is_nil(reason),
       reason: reason && Atom.to_string(reason),
       quota: Verifications.sponsor_quota(),
       window_days: Verifications.sponsor_quota_days(),
       used: used,
       left:
         if(Verifications.membership_verified?(standing),
           do: Verifications.quota_left(used),
           else: 0
         ),
       penalty_until: standing && standing.penalty_until
     }}
  end

  # The sponsor's own verification (verifying a member on first use), as a
  # standing with the vouches in the rolling window.
  defp standing(scope, user_id, now) do
    case PartnerEligibility.verification(scope) do
      nil ->
        nil

      verification ->
        %{
          method: verification.method,
          status: verification.status,
          penalty_until: verification.sponsor_penalty_until,
          vouches:
            Verifications.count_vouches_since(
              scope,
              user_id,
              Verifications.quota_window_start(now)
            )
        }
    end
  end

  defp check(%{user_id: user_id} = context, candidate_id, now) do
    blocked? = candidate_id in Community.blocked_user_ids(context)

    Verifications.check_sponsor(
      standing(scope(context), user_id, now),
      user_id,
      candidate_id,
      blocked?,
      now
    )
  end

  defp scope(%{user_id: user_id}), do: %{user_id: user_id}

  defp param(params, key) when is_map(params),
    do: Map.get(params, key) || Map.get(params, Atom.to_string(key))

  defp param(_params, _key), do: nil
end
