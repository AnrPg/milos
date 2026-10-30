defmodule Palee.Partners.Sponsorship do
  @moduledoc """
  A candidate's request to a sponsor and the sponsor's answer (ADR-280 §1):
  asked among the candidate's Buddies (`buddy`) or vouched through the
  candidate's link (`link`). One per pair.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Partners.Domain.SponsorPolicy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "partner_sponsorships" do
    field :candidate_id, :binary_id
    field :sponsor_id, :binary_id
    field :channel, :string
    field :status, :string, default: "requested"
    field :requested_at, :utc_datetime_usec
    field :decided_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(sponsorship \\ %__MODULE__{}, attrs) do
    sponsorship
    |> cast(attrs, ~w(candidate_id sponsor_id channel status requested_at decided_at)a)
    |> validate_required(~w(candidate_id sponsor_id channel status requested_at)a)
    |> validate_inclusion(:channel, SponsorPolicy.channels())
    |> validate_inclusion(:status, SponsorPolicy.statuses())
    |> check_constraint(:sponsor_id, name: :partner_sponsorships_pair_check)
    |> unique_constraint([:candidate_id, :sponsor_id])
  end
end
