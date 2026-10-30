defmodule Palee.Application.PartnerVerificationNotices do
  @moduledoc """
  The four notifications of Partners verification (ADR-280 §1): a sponsor
  is asked to vouch (`partner_vouch_request`), a candidate got a vouch
  (`partner_vouched`), the Palee check was decided or its selfie expired
  (`partner_verification_decided`), and a sponsor's 60-day pause after
  someone they vouched for was suspended (`partner_sponsor_penalty`, which
  never names that person). Personal notifications: no business.
  """

  alias Palee.Application.CommunityPeople
  alias Palee.Notifications

  def vouch_request(sponsorship) do
    Notifications.dispatch_event(:partner_vouch_request, %{
      user_id: sponsorship.sponsor_id,
      sponsorship_id: sponsorship.id,
      candidate_id: sponsorship.candidate_id,
      candidate_nickname: nickname(sponsorship.candidate_id),
      dedupe_key: "partner_vouch_request:#{sponsorship.id}:#{stamp(sponsorship.requested_at)}"
    })
  end

  def vouched(sponsorship) do
    Notifications.dispatch_event(:partner_vouched, %{
      user_id: sponsorship.candidate_id,
      sponsorship_id: sponsorship.id,
      sponsor_id: sponsorship.sponsor_id,
      sponsor_nickname: nickname(sponsorship.sponsor_id),
      dedupe_key: "partner_vouched:#{sponsorship.id}"
    })
  end

  @doc "`outcome` is `approved`, `rejected` or `expired` (the selfie must be taken again)."
  def decided(request, outcome) when outcome in ~w(approved rejected expired) do
    Notifications.dispatch_event(:partner_verification_decided, %{
      user_id: request.user_id,
      request_id: request.id,
      outcome: outcome,
      reason: if(outcome == "rejected", do: request.decision_reason),
      dedupe_key: "partner_verification_decided:#{request.id}:#{outcome}"
    })
  end

  def sponsor_penalty(sponsor_id, %DateTime{} = until) do
    until = until |> DateTime.to_date() |> Date.to_iso8601()

    Notifications.dispatch_event(:partner_sponsor_penalty, %{
      user_id: sponsor_id,
      until: until,
      dedupe_key: "partner_sponsor_penalty:#{sponsor_id}:#{until}"
    })
  end

  defp nickname(user_id),
    do:
      [user_id]
      |> CommunityPeople.by_ids()
      |> CommunityPeople.person(user_id)
      |> Map.get(:nickname)

  defp stamp(nil), do: "0"
  defp stamp(%DateTime{} = at), do: DateTime.to_unix(at)
end
