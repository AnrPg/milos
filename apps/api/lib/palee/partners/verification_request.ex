defmodule Palee.Partners.VerificationRequest do
  @moduledoc """
  The sponsor path's request (ADR-280 §1): consent, the phone (encrypted,
  plus a keyed hash so a number verifies one account only), the 4-digit
  selfie code, the selfie's object key while it exists, and the Palee
  team's decision.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Infrastructure.Security.EncryptedBinary
  alias Palee.Partners.Domain.VerificationReviewPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "partner_verification_requests" do
    field :user_id, :binary_id
    field :status, :string, default: "collecting"
    field :consent_at, :utc_datetime_usec
    field :phone_ciphertext, EncryptedBinary, redact: true
    field :phone_hash, :binary, redact: true
    field :phone_verified_at, :utc_datetime_usec
    field :selfie_code, :string
    field :selfie_key, :string
    field :selfie_uploaded_at, :utc_datetime_usec
    field :submitted_at, :utc_datetime_usec
    field :decided_at, :utc_datetime_usec
    field :decided_by_id, :binary_id
    field :decision_reason, :string

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(user_id status consent_at phone_ciphertext phone_hash phone_verified_at selfie_code
             selfie_key selfie_uploaded_at submitted_at decided_at decided_by_id decision_reason)a

  def changeset(request \\ %__MODULE__{}, attrs) do
    request
    |> cast(attrs, @fields)
    |> validate_required([:user_id, :status, :selfie_code])
    |> validate_inclusion(:status, VerificationReviewPolicy.statuses())
    |> validate_format(:selfie_code, ~r/^[0-9]{4}$/)
    |> validate_length(:decision_reason, max: VerificationReviewPolicy.reason_max())
    |> unique_constraint(:user_id, name: :partner_verification_requests_one_open_index)
    |> unique_constraint(:phone_hash, name: :partner_verification_requests_phone_taken)
  end
end
