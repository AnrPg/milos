defmodule Palee.Organizations.ProviderSelection do
  @moduledoc "The provider Box ▾ last opened on, remembered on the account (ADR-162)."

  use Ecto.Schema

  @primary_key {:user_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "account_provider_selections" do
    field(:organization_id, :binary_id)

    timestamps(type: :utc_datetime_usec)
  end
end
