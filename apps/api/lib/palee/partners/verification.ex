defmodule Palee.Partners.Verification do
  @moduledoc """
  A person's Partners verification (ADR-280 §1): once per account and
  permanent, by `membership` or by `sponsors` (two vouches and a check by
  the Palee team). Lost only by a suspension. `sponsor_penalty_until` is the
  60-day pause on vouching after someone the person vouched for was
  suspended.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "partner_verifications" do
    field :user_id, :binary_id
    field :method, :string
    field :status, :string, default: "verified"
    field :verified_at, :utc_datetime_usec
    field :source_organization_id, :binary_id
    field :suspended_at, :utc_datetime_usec
    field :suspended_by_id, :binary_id
    field :sponsor_penalty_until, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(user_id method status verified_at source_organization_id suspended_at
             suspended_by_id sponsor_penalty_until)a

  def changeset(verification \\ %__MODULE__{}, attrs) do
    verification
    |> cast(attrs, @fields)
    |> validate_required([:user_id, :method, :status, :verified_at])
    |> validate_inclusion(:method, ~w(membership sponsors))
    |> validate_inclusion(:status, ~w(verified suspended))
    |> unique_constraint(:user_id)
  end
end
