defmodule Palee.Partners.Ports.VerificationStore do
  @moduledoc """
  Persistence port of Partners verification (ADR-280 §1, §3): verifications,
  requests, phone codes, sponsorships and sponsor links. All rows are
  personal; the facade (`Palee.Partners.VerificationStore`) opens the
  session of the acting person or vendor (`app.user_id`), or none for the
  system, and row security does the rest. Adapters run inside that session.
  """

  alias Palee.Partners.{PhoneCode, SponsorLink, Sponsorship, Verification, VerificationRequest}

  @type id :: Ecto.UUID.t()
  @type standing :: %{
          method: String.t(),
          status: String.t(),
          penalty_until: DateTime.t() | nil,
          vouches: non_neg_integer()
        }

  @callback transaction((-> term())) :: {:ok, term()} | {:error, term()}

  # Verifications.
  @callback get_verification(user_id :: id) :: Verification.t() | nil
  @doc "Verifies the session's person by a membership when they hold one (idempotent)."
  @callback verify_by_membership() :: Verification.t() | nil
  @callback verification_badges([id]) :: %{id => %{method: String.t(), box_name: String.t() | nil}}
  @callback sponsor_standing([id], since :: DateTime.t()) :: %{id => standing()}
  @callback insert_verification(attrs :: map()) :: {:ok, Verification.t()} | {:error, term()}
  @callback update_verification(Verification.t(), changes :: map()) ::
              {:ok, Verification.t()} | {:error, term()}
  @callback list_verifications([id]) :: [Verification.t()]

  # Requests.
  @callback get_request(id) :: VerificationRequest.t() | nil
  @callback latest_request(user_id :: id) :: VerificationRequest.t() | nil
  @callback create_request(attrs :: map()) :: {:ok, VerificationRequest.t()} | {:error, term()}
  @callback update_request(VerificationRequest.t(), changes :: map()) ::
              {:ok, VerificationRequest.t()} | {:error, term()}
  @callback list_requests(status :: String.t(), limit :: pos_integer()) :: [VerificationRequest.t()]
  @callback requests_with_selfies_before(DateTime.t()) :: [VerificationRequest.t()]
  @callback requests_of(user_id :: id) :: [VerificationRequest.t()]

  # Phone codes.
  @callback count_codes_since(user_id :: id, since :: DateTime.t()) :: non_neg_integer()
  @callback insert_code(attrs :: map()) :: {:ok, PhoneCode.t()} | {:error, term()}
  @callback latest_code(request_id :: id) :: PhoneCode.t() | nil
  @callback update_code(PhoneCode.t(), changes :: map()) :: {:ok, PhoneCode.t()} | {:error, term()}
  @callback delete_code(PhoneCode.t()) :: :ok
  @callback delete_codes_before(DateTime.t()) :: non_neg_integer()

  # Sponsorships.
  @callback get_sponsorship(id) :: Sponsorship.t() | nil
  @callback sponsorship_between(candidate_id :: id, sponsor_id :: id) :: Sponsorship.t() | nil
  @callback sponsorships_of_candidate(candidate_id :: id) :: [Sponsorship.t()]
  @callback sponsorships_of_sponsor(sponsor_id :: id, statuses :: [String.t()]) :: [Sponsorship.t()]
  @callback count_vouches_since(sponsor_id :: id, since :: DateTime.t()) :: non_neg_integer()
  @callback insert_sponsorship(attrs :: map()) :: {:ok, Sponsorship.t()} | {:error, term()}
  @callback update_sponsorship(Sponsorship.t(), changes :: map()) ::
              {:ok, Sponsorship.t()} | {:error, term()}
  @callback delete_open_sponsorships(candidate_id :: id) :: non_neg_integer()
  @doc "Sponsors who vouched for the candidate."
  @callback vouched_sponsor_ids(candidate_id :: id) :: [id]

  # Links.
  @callback insert_link(attrs :: map()) :: {:ok, SponsorLink.t()} | {:error, term()}
  @callback delete_links(candidate_id :: id) :: non_neg_integer()
  @callback find_link(digest :: binary()) ::
              %{id: id, candidate_id: id, expires_at: DateTime.t(), used_at: DateTime.t() | nil}
              | nil
  @doc "Uses a live link once as the session's person: the candidate's id or nil."
  @callback redeem_link(digest :: binary(), DateTime.t()) :: id | nil

  # Account deletion.
  @doc "Deletes every verification row of the person; returns the selfie keys that existed."
  @callback purge_person(user_id :: id) :: [String.t()]
end
