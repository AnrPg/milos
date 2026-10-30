defmodule Palee.PersonalData.Ports.ExportStore do
  @moduledoc """
  ADR-267: storage of "Download my data" requests. Every call runs in the
  person's own session (`app.user_id`): the table's row-level security admits
  only the profile's own rows.
  """

  alias Palee.PersonalData.Export

  @type id :: Ecto.UUID.t()

  @doc "The profile's requests, newest first."
  @callback list(id()) :: [Export.t()]
  @callback get(id(), id()) :: Export.t() | nil
  @callback insert(map()) :: {:ok, Export.t()} | {:error, Ecto.Changeset.t()}

  @doc "Moves a pending request to `ready` or `failed` (row locked); other states are left."
  @callback finish(Export.t(), map()) ::
              {:ok, Export.t()} | {:error, :not_pending | Ecto.Changeset.t()}
end
