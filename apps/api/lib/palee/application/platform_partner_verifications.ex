defmodule Palee.Application.PlatformPartnerVerifications do
  @moduledoc """
  The Palee team's queue of the Partners check (ADR-280 §2, §5, option A):
  requests in review, one request with a 5-minute link to the selfie, its
  4-digit code, the person's avatar to compare with, the sponsors and the
  masked phone; and the decision. No face recognition and no automatic
  decision: a person compares and decides.

  A decision keeps only the outcome: the selfie is deleted and the phone's
  ciphertext goes (its keyed hash stays so the number cannot verify another
  account). Approving records the `sponsors` verification.
  """

  alias Palee.Application.{CommunityPeople, PartnerSelfieStorage, PartnerVerificationNotices}
  alias Palee.Partners.Verifications

  @limit 200

  @doc "Requests in a status (default `in_review`), oldest submission first."
  def list(%{user_id: _} = platform_context, params \\ %{}, now \\ DateTime.utc_now()) do
    scope = scope(platform_context)
    status = param(params, :status) || "in_review"

    with true <-
           status in Verifications.request_statuses() ||
             {:error, :invalid_partner_verification_status} do
      requests = Verifications.list_requests(scope, status, @limit)
      people = CommunityPeople.by_ids(Enum.map(requests, & &1.user_id))

      {:ok,
       %{
         requests:
           Enum.map(requests, fn request ->
             %{
               id: request.id,
               status: request.status,
               person: CommunityPeople.person(people, request.user_id),
               submitted_at: request.submitted_at,
               selfie_expires_at: Verifications.selfie_expires_at(request.selfie_uploaded_at),
               overdue: Verifications.selfie_expired?(request, now)
             }
           end)
       }}
    end
  end

  @doc "One request as the reviewer sees it, with a 5-minute selfie link."
  def show(%{user_id: _} = platform_context, request_id) do
    scope = scope(platform_context)

    with %{} = request <- Verifications.get_request(scope, request_id) || {:error, :not_found},
         {:ok, selfie_url} <- selfie_url(request) do
      sponsorships =
        scope
        |> Verifications.sponsorships_of_candidate(request.user_id)
        |> Enum.filter(&(&1.status == "vouched"))

      people = CommunityPeople.by_ids([request.user_id | Enum.map(sponsorships, & &1.sponsor_id)])

      {:ok,
       %{
         id: request.id,
         status: request.status,
         person: CommunityPeople.person(people, request.user_id),
         selfie_code: request.selfie_code,
         selfie_url: selfie_url,
         selfie_url_expires_in: PartnerSelfieStorage.view_seconds(),
         selfie_uploaded_at: request.selfie_uploaded_at,
         selfie_expires_at: Verifications.selfie_expires_at(request.selfie_uploaded_at),
         phone: Verifications.mask_phone(request.phone_ciphertext),
         phone_verified: not is_nil(request.phone_verified_at),
         consent_at: request.consent_at,
         submitted_at: request.submitted_at,
         decided_at: request.decided_at,
         decision_reason: request.decision_reason,
         sponsors:
           Enum.map(sponsorships, fn sponsorship ->
             %{
               person: CommunityPeople.person(people, sponsorship.sponsor_id),
               channel: sponsorship.channel,
               vouched_at: sponsorship.decided_at
             }
           end)
       }}
    end
  end

  defp selfie_url(%{selfie_key: nil}), do: {:ok, nil}
  defp selfie_url(request), do: PartnerSelfieStorage.view_url(request.user_id, request.selfie_key)

  @doc "Approves or rejects a request in review (`decision`, `reason` required to reject)."
  def decide(
        %{user_id: actor_id} = platform_context,
        request_id,
        params,
        now \\ DateTime.utc_now()
      ) do
    scope = scope(platform_context)

    with {:ok, %{decision: decision, reason: reason}} <-
           Verifications.normalize_review_decision(params),
         %{} = request <- Verifications.get_request(scope, request_id) || {:error, :not_found},
         :ok <- Verifications.check_decidable(request),
         {:ok, decided} <-
           Verifications.transaction(scope, fn ->
             record(scope, request, decision, reason, actor_id, now)
           end) do
      PartnerSelfieStorage.delete_under(request.user_id, request.id)
      PartnerVerificationNotices.decided(decided, decided.status)
      {:ok, %{id: decided.id, status: decided.status, decided_at: decided.decided_at}}
    end
  end

  defp record(scope, request, decision, reason, actor_id, now) do
    with {:ok, decided} <-
           Verifications.update_request(
             scope,
             request,
             Verifications.decision_changes(decision, reason, actor_id, now)
           ),
         {:ok, _verification} <- verify(scope, decision, request.user_id, now) do
      {:ok, decided}
    end
  end

  defp verify(_scope, "reject", _user_id, _now), do: {:ok, nil}

  defp verify(scope, "approve", user_id, now) do
    case Verifications.get_verification(scope, user_id) do
      # Verified meanwhile (say, by a membership): the first verification stays.
      %{} = verification ->
        {:ok, verification}

      nil ->
        Verifications.insert_verification(scope, %{
          user_id: user_id,
          method: "sponsors",
          status: "verified",
          verified_at: now
        })
    end
  end

  defp scope(%{user_id: user_id}), do: %{user_id: user_id}

  defp param(params, key) when is_map(params),
    do: Map.get(params, key) || Map.get(params, Atom.to_string(key))

  defp param(_params, _key), do: nil
end
