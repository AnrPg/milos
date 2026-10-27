defmodule Palee.Email.OptOut do
  @moduledoc """
  An address that unsubscribed from one transactional kind (ADR-212,
  List-Unsubscribe). Security and account mail never read it.
  """

  use Ecto.Schema

  @primary_key false

  @type t :: %__MODULE__{}

  schema "email_opt_outs" do
    field :address_digest, :binary, primary_key: true
    field :kind, :string, primary_key: true

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
