defmodule Palee.Email.Suppression do
  @moduledoc """
  An address Palee no longer mails (ADR-203), by its
  `InvitationEmail.digest/1`: `bounce`, `complaint` or `manual`.
  """

  use Ecto.Schema

  @primary_key {:address_digest, :binary, autogenerate: false}

  @type t :: %__MODULE__{}

  @reasons ~w(bounce complaint manual)

  schema "email_suppressions" do
    field :reason, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc "The reasons an address can be suppressed for."
  def reasons, do: @reasons
end
