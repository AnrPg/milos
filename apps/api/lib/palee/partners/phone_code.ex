defmodule Palee.Partners.PhoneCode do
  @moduledoc "An SMS code of the sponsor path (ADR-280 §1), stored only as a keyed hash."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{}

  schema "partner_phone_codes" do
    field :request_id, :binary_id
    field :user_id, :binary_id
    field :code_hash, :binary, redact: true
    field :expires_at, :utc_datetime_usec
    field :attempts, :integer, default: 0
    field :sent_at, :utc_datetime_usec
    field :consumed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(code \\ %__MODULE__{}, attrs) do
    code
    |> cast(attrs, ~w(request_id user_id code_hash expires_at attempts sent_at consumed_at)a)
    |> validate_required(~w(request_id user_id code_hash expires_at sent_at)a)
    |> validate_number(:attempts, greater_than_or_equal_to: 0, less_than_or_equal_to: 5)
  end
end
