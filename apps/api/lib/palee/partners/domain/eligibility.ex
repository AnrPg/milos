defmodule Palee.Partners.Domain.Eligibility do
  @moduledoc """
  Who may take part in Partners (ADR-280 §2): a person verified once (by an
  active membership, or by two sponsors and a check by the Palee team),
  never suspended. Pure: the caller passes the person's verification row,
  their latest verification request and how many sponsors vouched.

  The next step of the sponsor path, in order: `:consent`, `:sponsors`,
  `:phone`, `:selfie`; nil while nothing is left for the person to do.
  """

  alias Palee.Partners.Domain.{SponsorPolicy, VerificationReviewPolicy}

  @type status :: :verified | :needs_verification | :in_review | :rejected | :suspended
  @type step :: :consent | :sponsors | :phone | :selfie | nil

  @statuses ~w(verified needs_verification in_review rejected suspended)a
  @steps ~w(consent sponsors phone selfie)a

  def statuses, do: @statuses
  def steps, do: @steps

  @doc "The person's state, how they were verified and their next step."
  @spec status(map() | nil, map() | nil, non_neg_integer()) :: %{
          status: status(),
          method: String.t() | nil,
          next_step: step()
        }
  def status(verification, request, vouches \\ 0)

  def status(%{status: "suspended", method: method}, _request, _vouches),
    do: %{status: :suspended, method: method, next_step: nil}

  def status(%{status: "verified", method: method}, _request, _vouches),
    do: %{status: :verified, method: method, next_step: nil}

  def status(_none, %{status: "in_review"}, _vouches),
    do: %{status: :in_review, method: nil, next_step: nil}

  def status(_none, %{status: "rejected"}, _vouches),
    do: %{status: :rejected, method: nil, next_step: :consent}

  def status(_none, %{status: status} = request, vouches)
      when status in ["collecting", "expired"],
      do: %{status: :needs_verification, method: nil, next_step: next_step(request, vouches)}

  def status(_none, _request, _vouches),
    do: %{status: :needs_verification, method: nil, next_step: :consent}

  @doc "The first thing the open request still lacks."
  def next_step(request, vouches) do
    cond do
      is_nil(Map.get(request, :consent_at)) -> :consent
      vouches < SponsorPolicy.required() -> :sponsors
      is_nil(Map.get(request, :phone_verified_at)) -> :phone
      true -> :selfie
    end
  end

  @doc "Verified and not suspended."
  def verified?(%{status: "verified"}), do: true
  def verified?(_verification), do: false

  @doc "`:ok` when the person may use Partners."
  @spec require_verified(map() | nil) ::
          :ok | {:error, :partner_verification_required} | {:error, :partner_suspended}
  def require_verified(%{status: "verified"}), do: :ok
  def require_verified(%{status: "suspended"}), do: {:error, :partner_suspended}
  def require_verified(_verification), do: {:error, :partner_verification_required}

  @doc """
  Whether the person may start or continue the sponsor path: not verified
  already, not suspended, and no request in review.
  """
  def check_can_apply(%{status: "verified"}, _request), do: {:error, :partner_already_verified}
  def check_can_apply(%{status: "suspended"}, _request), do: {:error, :partner_suspended}

  def check_can_apply(_verification, request) do
    if VerificationReviewPolicy.in_review?(request),
      do: {:error, :partner_verification_in_review},
      else: :ok
  end
end
