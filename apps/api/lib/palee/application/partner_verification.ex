defmodule Palee.Application.PartnerVerification do
  @moduledoc """
  The person's side of Partners verification (ADR-280 §2, §5): where they
  stand, and the sponsor path for people without an active membership.

  1. Consent (`consent/2`) opens the request and gives its 4-digit selfie
     code.
  2. Two sponsors vouch: asked among the person's verified Buddies
     (`sponsor_candidates/2`, `request_sponsor/3`, `cancel_sponsor/2`) or
     through a single-use 10-minute link (`create_link/2`).
  3. An SMS code to one mobile number (`send_phone_code/3`,
     `confirm_phone/3`).
  4. A selfie holding the code on paper (`selfie_upload_url/2`), then the
     submission to the Palee team (`submit/3`).
  `withdraw/2` drops the request with its phone, selfie, open sponsor
  requests and links. A person with an active membership is verified
  without any of this, on first use.
  """

  alias Palee.Application.{
    CommunityPeople,
    KeyDerivation,
    PartnerEligibility,
    PartnerSelfieStorage,
    PartnerVerificationNotices,
    PublicURL,
    Sms
  }

  alias Palee.{Community, Identity}
  alias Palee.Partners.Verifications

  # -------------------------------------------------------------- overview

  @doc "The person's verification state, their open (or last) request and the limits."
  def overview(%{user_id: user_id} = context, now \\ DateTime.utc_now()) do
    scope = scope(context)
    verification = PartnerEligibility.verification(scope)
    request = Verifications.latest_request(scope, user_id)
    request = tidy(scope, verification, request, now)
    sponsorships = if request, do: Verifications.sponsorships_of_candidate(scope, user_id), else: []
    vouches = Verifications.vouch_count(sponsorships)
    eligibility = Verifications.status(verification, request, vouches)

    {:ok,
     %{
       eligibility: present_eligibility(eligibility),
       request: request && present_request(request, sponsorships, vouches),
       limits: limits()
     }}
  end

  # A person verified meanwhile (say, by a new membership) needs no open
  # request: it is withdrawn, with its phone and selfie.
  defp tidy(scope, %{status: _status}, request, now) do
    if Verifications.request_open?(request) do
      {:ok, withdrawn} = close(scope, request, now)
      withdrawn
    else
      request
    end
  end

  defp tidy(_scope, nil, request, _now), do: request

  # -------------------------------------------------------------- consent

  @doc "The person agrees to the Palee check: opens (or keeps) their request."
  def consent(%{user_id: user_id} = context, now \\ DateTime.utc_now()) do
    scope = scope(context)
    verification = PartnerEligibility.verification(scope)
    request = Verifications.latest_request(scope, user_id)

    with :ok <- Verifications.check_can_apply(verification, request),
         {:ok, _request} <- open_request(scope, user_id, request, now) do
      overview(context, now)
    end
  end

  defp open_request(scope, user_id, request, now) do
    cond do
      Verifications.request_open?(request) and is_nil(request.consent_at) ->
        Verifications.update_request(scope, request, %{consent_at: now})

      Verifications.request_open?(request) ->
        {:ok, request}

      true ->
        code = Verifications.selfie_code_from(random())
        Verifications.create_request(scope, Verifications.new_request(user_id, code, now))
    end
  end

  # -------------------------------------------------------------- sponsors

  @doc """
  The person's Buddies (mutual follows, ADR-193) as possible sponsors, each
  marked whether they may vouch now and, if not, why (`not_verified`,
  `blocked`, `quota`, `penalty`); with any request already made to them.
  """
  def sponsor_candidates(%{user_id: user_id} = context, now \\ DateTime.utc_now()) do
    scope = scope(context)
    ids = buddy_ids(context, user_id)
    standing = Verifications.sponsor_standing(scope, ids, Verifications.quota_window_start(now))

    asked =
      scope
      |> Verifications.sponsorships_of_candidate(user_id)
      |> Map.new(&{&1.sponsor_id, &1})

    people = CommunityPeople.by_ids(ids)

    candidates =
      ids
      |> Enum.map(fn id ->
        reason = Verifications.sponsor_reason(Map.get(standing, id), id, user_id, false, now)

        %{
          person: CommunityPeople.person(people, id),
          eligible: is_nil(reason),
          reason: reason && Atom.to_string(reason),
          sponsorship: asked |> Map.get(id) |> present_sponsorship_state()
        }
      end)
      |> Enum.sort_by(&{not &1.eligible, String.downcase(&1.person.nickname || "~")})

    {:ok,
     %{
       candidates: candidates,
       required: Verifications.sponsors_required(),
       vouches: asked |> Map.values() |> Verifications.vouch_count()
     }}
  end

  # Buddies the person can see, minus anyone blocked either way.
  defp buddy_ids(context, user_id) do
    blocked = MapSet.new(Community.blocked_user_ids(context))

    context
    |> Community.buddy_ids(user_id)
    |> Identity.visible_user_ids(user_id)
    |> Enum.reject(&MapSet.member?(blocked, &1))
    |> Enum.uniq()
  end

  @doc "Asks a Buddy to vouch (`sponsor_id`); they get a notification."
  def request_sponsor(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    scope = scope(context)

    with {:ok, sponsor_id} <- cast_id(param(params, :sponsor_id)),
         {:ok, _request} <- editable_request(scope, user_id),
         true <- sponsor_id in buddy_ids(context, user_id) || {:error, :partner_sponsor_not_eligible},
         standing = Verifications.sponsor_standing(scope, [sponsor_id], window(now)),
         :ok <-
           Verifications.check_sponsor(
             Map.get(standing, sponsor_id),
             sponsor_id,
             user_id,
             false,
             now
           ),
         {:ok, sponsorship, new?} <- ask(scope, user_id, sponsor_id, now) do
      if new?, do: PartnerVerificationNotices.vouch_request(sponsorship)
      {:ok, %{sponsorship: present_sponsorship(sponsorship, CommunityPeople.by_ids([sponsor_id]))}}
    end
  end

  defp ask(scope, user_id, sponsor_id, now) do
    case Verifications.ask_sponsor(
           Verifications.sponsorship_between(scope, user_id, sponsor_id),
           now
         ) do
      :insert ->
        with {:ok, sponsorship} <-
               Verifications.insert_sponsorship(scope, %{
                 candidate_id: user_id,
                 sponsor_id: sponsor_id,
                 channel: "buddy",
                 status: "requested",
                 requested_at: now
               }),
             do: {:ok, sponsorship, true}

      {:update, changes} ->
        sponsorship = Verifications.sponsorship_between(scope, user_id, sponsor_id)

        with {:ok, sponsorship} <- Verifications.update_sponsorship(scope, sponsorship, changes),
             do: {:ok, sponsorship, true}

      {:keep, sponsorship} ->
        {:ok, sponsorship, false}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Withdraws a request to a sponsor (`sponsor_id`) that is still unanswered."
  def cancel_sponsor(%{user_id: user_id} = context, sponsor_id) do
    scope = scope(context)

    with {:ok, sponsor_id} <- cast_id(sponsor_id),
         %{} = sponsorship <-
           Verifications.sponsorship_between(scope, user_id, sponsor_id) || {:error, :not_found},
         {:ok, changes} <- Verifications.cancel_sponsorship(sponsorship),
         {:ok, sponsorship} <- Verifications.update_sponsorship(scope, sponsorship, changes) do
      {:ok, %{sponsorship: present_sponsorship(sponsorship, CommunityPeople.by_ids([sponsor_id]))}}
    end
  end

  @doc """
  A single-use link (and its QR) for someone who knows the person but is
  not among their Buddies; lives 10 minutes. The token is shown once.
  """
  def create_link(%{user_id: user_id} = context, now \\ DateTime.utc_now()) do
    scope = scope(context)
    token = 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    with {:ok, _request} <- editable_request(scope, user_id),
         _deleted = Verifications.delete_links(scope, user_id),
         {:ok, link} <-
           Verifications.insert_link(scope, %{
             candidate_id: user_id,
             token_hash: Verifications.link_digest(token),
             expires_at: Verifications.link_expires_at(now)
           }) do
      path = "/partners/vouch#token=" <> token
      {:ok, %{token: token, path: path, url: PublicURL.base_url() <> path, expires_at: link.expires_at}}
    end
  end

  # -------------------------------------------------------------- phone

  @doc "Sends a 6-digit code to the mobile number (`phone`)."
  def send_phone_code(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    scope = scope(context)
    {hour_ago, day_ago} = Verifications.send_windows(now)

    with {:ok, request} <- editable_request(scope, user_id),
         {:ok, phone} <- Verifications.normalize_phone(param(params, :phone)),
         :ok <-
           Verifications.check_send_rate(
             Verifications.count_codes_since(scope, user_id, hour_ago),
             Verifications.count_codes_since(scope, user_id, day_ago)
           ),
         {:ok, request} <-
           Verifications.update_request(scope, request, %{
             phone_ciphertext: phone,
             phone_hash: KeyDerivation.derive("partner-phone", phone),
             phone_verified_at: nil
           }),
         code = Verifications.code_from(random()),
         {:ok, row} <-
           Verifications.insert_code(scope, %{
             request_id: request.id,
             user_id: user_id,
             code_hash: code_hash(request.id, code),
             expires_at: Verifications.code_expires_at(now),
             sent_at: now
           }),
         :ok <- deliver(scope, row, phone, code) do
      {:ok,
       %{
         phone: Verifications.mask_phone(phone),
         expires_at: row.expires_at,
         code_minutes: Verifications.code_minutes()
       }}
    end
  end

  defp deliver(scope, row, phone, code) do
    case Sms.deliver(%{to: phone, body: Verifications.sms_body(code), tag: "partner-verification"}) do
      :ok ->
        :ok

      {:error, _reason} ->
        # Not sent, not counted against the person's limits.
        :ok = Verifications.delete_code(scope, row)
        {:error, :sms_unavailable}
    end
  end

  @doc "Confirms the number with the code it received (`code`)."
  def confirm_phone(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    scope = scope(context)

    with {:ok, request} <- editable_request(scope, user_id),
         true <- not is_nil(request.phone_hash) || {:error, :partner_code_invalid},
         {:ok, code} <- Verifications.normalize_code(param(params, :code)),
         row = Verifications.latest_code(scope, request.id),
         :ok <- Verifications.check_code(row, now),
         :ok <- match_code(scope, row, request.id, code, now),
         {:ok, _request} <-
           Verifications.update_request(scope, request, %{phone_verified_at: now}) do
      overview(context, now)
    end
  end

  defp match_code(scope, row, request_id, code, now) do
    if Plug.Crypto.secure_compare(code_hash(request_id, code), row.code_hash) do
      {:ok, _row} = Verifications.update_code(scope, row, %{consumed_at: now})
      :ok
    else
      {:ok, _row} = Verifications.update_code(scope, row, %{attempts: row.attempts + 1})
      {:error, :partner_code_invalid}
    end
  end

  defp code_hash(request_id, code),
    do: KeyDerivation.derive("partner-phone-code", request_id <> ":" <> code)

  # -------------------------------------------------------------- selfie

  @doc "A presigned upload for the selfie (`content_type`), with the code to hold up."
  def selfie_upload_url(%{user_id: user_id} = context, params) do
    scope = scope(context)

    with {:ok, request} <- editable_request(scope, user_id),
         {:ok, upload} <- Verifications.validate_selfie_upload(param(params, :content_type)),
         key = Verifications.selfie_key(user_id, request.id, upload.extension),
         {:ok, presigned} <- PartnerSelfieStorage.upload(user_id, key, upload.content_type) do
      {:ok,
       %{
         upload_url: presigned.url,
         method: "PUT",
         required_headers: presigned.headers,
         file_key: key,
         content_type: upload.content_type,
         max_bytes: upload.max_bytes,
         selfie_code: request.selfie_code
       }}
    end
  end

  @doc """
  Sends the request to the Palee team with the uploaded selfie (`file_key`):
  consent, two vouches and a verified phone must be there.
  """
  def submit(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    scope = scope(context)
    key = param(params, :file_key)

    with {:ok, request} <- editable_request(scope, user_id),
         content_type when is_binary(content_type) <-
           Verifications.selfie_content_type(key, user_id, request.id) ||
             {:error, :document_key_forbidden},
         vouches =
           scope |> Verifications.sponsorships_of_candidate(user_id) |> Verifications.vouch_count(),
         :ok <- discard_on_error(user_id, key, Verifications.check_submittable(request, vouches)),
         {:ok, probe} <- PartnerSelfieStorage.probe(user_id, key, Verifications.selfie_probe_bytes()),
         :ok <-
           discard_on_error(
             user_id,
             key,
             Verifications.validate_selfie_file(content_type, probe.head, probe.byte_size)
           ),
         {:ok, _submitted} <-
           Verifications.update_request(scope, request, Verifications.submit_changes(key, now)) do
      if request.selfie_key && request.selfie_key != key,
        do: PartnerSelfieStorage.delete(user_id, request.selfie_key)

      overview(context, now)
    end
  end

  defp discard_on_error(_user_id, _key, :ok), do: :ok

  defp discard_on_error(user_id, key, error) do
    PartnerSelfieStorage.delete(user_id, key)
    error
  end

  # -------------------------------------------------------------- withdraw

  @doc "Withdraws the open request: phone, selfie, open sponsor requests and links go."
  def withdraw(%{user_id: user_id} = context, now \\ DateTime.utc_now()) do
    scope = scope(context)
    request = Verifications.latest_request(scope, user_id)

    with true <- Verifications.request_open?(request) || {:error, :not_found},
         {:ok, _withdrawn} <- close(scope, request, now) do
      overview(context, now)
    end
  end

  defp close(scope, request, _now) do
    with {:ok, withdrawn} <-
           Verifications.update_request(scope, request, Verifications.withdraw_changes()) do
      PartnerSelfieStorage.delete_under(request.user_id, request.id)
      _count = Verifications.delete_open_sponsorships(scope, request.user_id)
      _count = Verifications.delete_links(scope, request.user_id)
      {:ok, withdrawn}
    end
  end

  # -------------------------------------------------------------- shared

  # The open request the person may still change (not in review, consented).
  defp editable_request(scope, user_id) do
    verification = PartnerEligibility.verification(scope)
    request = Verifications.latest_request(scope, user_id)

    with :ok <- Verifications.check_can_apply(verification, request),
         :ok <- Verifications.check_editable(open_or_nil(request)) do
      {:ok, request}
    end
  end

  defp open_or_nil(request), do: if(Verifications.request_open?(request), do: request)

  defp window(now), do: Verifications.quota_window_start(now)

  defp limits do
    %{
      sponsors_required: Verifications.sponsors_required(),
      link_minutes: Verifications.link_minutes(),
      code_minutes: Verifications.code_minutes(),
      code_attempts: Verifications.code_max_attempts(),
      selfie_content_types: Verifications.selfie_content_types(),
      selfie_max_bytes: Verifications.selfie_max_bytes(),
      selfie_retention_days: Verifications.selfie_retention_days()
    }
  end

  @doc false
  def present_eligibility(%{status: status, method: method, next_step: next_step}),
    do: %{status: Atom.to_string(status), method: method, next_step: next_step && Atom.to_string(next_step)}

  defp present_request(request, sponsorships, vouches) do
    people = CommunityPeople.by_ids(Enum.map(sponsorships, & &1.sponsor_id))

    %{
      id: request.id,
      status: request.status,
      consent_at: request.consent_at,
      vouches: vouches,
      sponsors_required: Verifications.sponsors_required(),
      sponsors:
        sponsorships
        |> Enum.filter(&(&1.status in ["requested", "vouched"]))
        |> Enum.map(&present_sponsorship(&1, people)),
      phone: Verifications.mask_phone(request.phone_ciphertext),
      phone_verified: not is_nil(request.phone_verified_at),
      selfie_code: request.selfie_code,
      selfie_uploaded_at: request.selfie_uploaded_at,
      selfie_expires_at: Verifications.selfie_expires_at(request.selfie_uploaded_at),
      submitted_at: request.submitted_at,
      decided_at: request.decided_at,
      decision_reason: request.decision_reason,
      missing: request |> Verifications.missing_steps(vouches) |> Enum.map(&Atom.to_string/1)
    }
  end

  @doc false
  def present_sponsorship(sponsorship, people) do
    %{
      id: sponsorship.id,
      person: CommunityPeople.person(people, sponsorship.sponsor_id),
      channel: sponsorship.channel,
      status: sponsorship.status,
      requested_at: sponsorship.requested_at,
      decided_at: sponsorship.decided_at
    }
  end

  defp present_sponsorship_state(nil), do: nil

  defp present_sponsorship_state(sponsorship),
    do: %{id: sponsorship.id, status: sponsorship.status, channel: sponsorship.channel}

  defp random, do: 4 |> :crypto.strong_rand_bytes() |> :binary.decode_unsigned()

  defp scope(%{user_id: user_id}), do: %{user_id: user_id}

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :invalid_user}
    end
  end

  defp param(params, key) when is_map(params),
    do: Map.get(params, key) || Map.get(params, Atom.to_string(key))

  defp param(_params, _key), do: nil
end
