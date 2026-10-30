defmodule Palee.Partners.Domain.VerificationReviewPolicy do
  @moduledoc """
  The Palee check of the sponsor path (ADR-280 §2, option A).

  A request is open while `collecting`, `in_review` or `expired` (the selfie
  was deleted unreviewed; the person takes a new one). It may be submitted
  when it holds the consent, 2 vouches, a verified phone and a selfie of the
  person holding the request's 4-digit code on paper. A person of the Palee
  team approves or rejects it (a reason is required to reject); nothing is
  decided automatically.

  The selfie (JPEG, PNG, WebP or HEIC, at most 8 MB) lives under
  `users/<user id>/partner-verification/<request id>.<ext>` and is deleted
  on the decision, on withdrawal, on account deletion and at the latest 7
  days after upload. The phone's ciphertext goes with the decision; its
  keyed hash stays, so the number cannot verify another account.
  """

  alias Palee.Partners.Domain.SponsorPolicy

  @statuses ~w(collecting in_review approved rejected expired withdrawn)
  @open ~w(collecting in_review expired)
  @decisions ~w(approve reject)
  @reason_max 500
  @retention_days 7
  @max_bytes 8 * 1024 * 1024
  @probe_bytes 16
  @content_types %{
    "image/jpeg" => ".jpg",
    "image/png" => ".png",
    "image/webp" => ".webp",
    "image/heic" => ".heic"
  }
  @heic_brands ~w(heic heix hevc hevx mif1 msf1)

  def statuses, do: @statuses
  def open_statuses, do: @open
  def decisions, do: @decisions
  def reason_max, do: @reason_max
  def retention_days, do: @retention_days
  def max_bytes, do: @max_bytes
  def probe_bytes, do: @probe_bytes
  def content_types, do: Map.keys(@content_types)

  def open?(%{status: status}), do: status in @open
  def open?(_request), do: false

  def in_review?(%{status: "in_review"}), do: true
  def in_review?(_request), do: false

  @doc "Whether the person may still change the request (not while in review)."
  def editable?(%{status: status}), do: status in ["collecting", "expired"]
  def editable?(_request), do: false

  @doc "`:ok` while the request can take the next step."
  def check_editable(nil), do: {:error, :partner_consent_required}

  def check_editable(request) do
    cond do
      in_review?(request) -> {:error, :partner_verification_in_review}
      not editable?(request) -> {:error, :partner_consent_required}
      is_nil(request.consent_at) -> {:error, :partner_consent_required}
      true -> :ok
    end
  end

  @doc "The 4-digit code to write on paper, from a random non-negative integer."
  def selfie_code_from(random) when is_integer(random) and random >= 0,
    do: random |> rem(10_000) |> Integer.to_string() |> String.pad_leading(4, "0")

  @doc "A new request's attributes."
  def new_request(user_id, selfie_code, %DateTime{} = now),
    do: %{user_id: user_id, status: "collecting", consent_at: now, selfie_code: selfie_code}

  # -- the selfie --------------------------------------------------------------

  @doc "`{:ok, %{content_type, extension, max_bytes}}` for an upload of this type."
  def validate_upload(content_type) do
    case Map.fetch(@content_types, content_type) do
      {:ok, extension} ->
        {:ok, %{content_type: content_type, extension: extension, max_bytes: @max_bytes}}

      :error ->
        {:error, {:invalid_fields, %{content_type: "unsupported"}}}
    end
  end

  @doc "The selfie's object key."
  def selfie_key(user_id, request_id, extension),
    do: "users/#{user_id}/partner-verification/#{request_id}#{extension}"

  @doc "The content type of a key this policy made for the request (nil otherwise)."
  def selfie_content_type(key, user_id, request_id) when is_binary(key) do
    Enum.find_value(@content_types, fn {content_type, extension} ->
      if key == selfie_key(user_id, request_id, extension), do: content_type
    end)
  end

  def selfie_content_type(_key, _user_id, _request_id), do: nil

  @doc "Checks the uploaded bytes against the type: `:ok` or `{:error, :partner_selfie_missing}`."
  def validate_file(content_type, head, byte_size) do
    if is_integer(byte_size) and byte_size > 0 and byte_size <= @max_bytes and
         magic?(content_type, head),
       do: :ok,
       else: {:error, :partner_selfie_invalid}
  end

  defp magic?("image/jpeg", <<0xFF, 0xD8, 0xFF, _::binary>>), do: true
  defp magic?("image/png", <<0x89, "PNG", _::binary>>), do: true
  defp magic?("image/webp", <<"RIFF", _size::binary-size(4), "WEBP", _::binary>>), do: true

  defp magic?("image/heic", <<_size::binary-size(4), "ftyp", brand::binary-size(4), _::binary>>),
    do: brand in @heic_brands

  defp magic?(_type, _head), do: false

  # -- submitting --------------------------------------------------------------

  @doc "What the request still lacks before it can be submitted (selfie aside)."
  def missing(request, vouches) do
    []
    |> add_if(is_nil(request.consent_at), :consent)
    |> add_if(not SponsorPolicy.enough?(vouches), :sponsors)
    |> add_if(is_nil(request.phone_verified_at), :phone)
    |> Enum.reverse()
  end

  defp add_if(list, true, item), do: [item | list]
  defp add_if(list, false, _item), do: list

  @doc "`:ok` when consent, vouches and phone are there."
  def check_submittable(request, vouches) do
    case missing(request, vouches) do
      [] -> :ok
      _missing -> {:error, :partner_verification_incomplete}
    end
  end

  @doc "The changes of a submission with the uploaded selfie."
  def submit_changes(key, %DateTime{} = now),
    do: %{status: "in_review", selfie_key: key, selfie_uploaded_at: now, submitted_at: now}

  @doc "When a selfie uploaded at `uploaded_at` is deleted unreviewed."
  def selfie_expires_at(nil), do: nil
  def selfie_expires_at(%DateTime{} = uploaded_at), do: DateTime.add(uploaded_at, @retention_days * 86_400)

  @doc "Selfies uploaded before this are past retention."
  def retention_cutoff(%DateTime{} = now), do: DateTime.add(now, -@retention_days * 86_400)

  @doc "Whether an in-review request's selfie is past retention."
  def selfie_expired?(%{status: "in_review", selfie_uploaded_at: %DateTime{} = at}, now),
    do: DateTime.compare(at, retention_cutoff(now)) != :gt

  def selfie_expired?(_request, _now), do: false

  @doc "The changes when the selfie expired unreviewed: the person retakes it."
  def expire_changes,
    do: %{status: "expired", selfie_key: nil, selfie_uploaded_at: nil, submitted_at: nil}

  @doc "The changes of a withdrawal: phone, selfie and review data go."
  def withdraw_changes do
    %{
      status: "withdrawn",
      phone_ciphertext: nil,
      phone_hash: nil,
      phone_verified_at: nil,
      selfie_key: nil,
      selfie_uploaded_at: nil
    }
  end

  # -- deciding ----------------------------------------------------------------

  @doc "`{:ok, %{decision, reason}}` from the platform's decision body."
  def normalize_decision(params) when is_map(params) do
    decision = value(params, :decision)
    reason = value(params, :reason)
    reason = if is_binary(reason), do: String.trim(reason), else: nil
    reason = if reason == "", do: nil, else: reason

    cond do
      decision not in @decisions -> {:error, :invalid_partner_verification_decision}
      decision == "reject" and is_nil(reason) -> {:error, :partner_decision_reason_required}
      reason && String.length(reason) > @reason_max -> {:error, :partner_decision_reason_too_long}
      true -> {:ok, %{decision: decision, reason: reason}}
    end
  end

  def normalize_decision(_params), do: {:error, :invalid_partner_verification_decision}

  @doc "`:ok` when the request waits for a decision."
  def check_decidable(%{status: "in_review"}), do: :ok
  def check_decidable(_request), do: {:error, :partner_verification_closed}

  @doc "The changes of a decision: the outcome stays, the phone and selfie go."
  def decision_changes(decision, reason, actor_id, %DateTime{} = now) do
    %{
      status: if(decision == "approve", do: "approved", else: "rejected"),
      decided_at: now,
      decided_by_id: actor_id,
      decision_reason: reason,
      phone_ciphertext: nil,
      selfie_key: nil
    }
  end

  defp value(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
