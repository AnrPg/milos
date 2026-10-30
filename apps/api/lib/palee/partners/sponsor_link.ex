defmodule Palee.Partners.SponsorLink do
  @moduledoc "A candidate's single-use, 10-minute sponsor link (ADR-280 §1); only its digest is kept."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "partner_sponsor_links" do
    field :candidate_id, :binary_id
    field :token_hash, :binary, redact: true
    field :expires_at, :utc_datetime_usec
    field :used_by_id, :binary_id
    field :used_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(link \\ %__MODULE__{}, attrs) do
    link
    |> cast(attrs, ~w(candidate_id token_hash expires_at used_by_id used_at)a)
    |> validate_required(~w(candidate_id token_hash expires_at)a)
    |> unique_constraint(:token_hash)
  end
end
