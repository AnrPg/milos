defmodule Palee.PersonalData.Ports.RecordSource do
  @moduledoc """
  ADR-267: reads the rows a `Catalog` entry holds for one person. The
  facade opens the session (the person's own, or a business's with the
  person acting); an adapter only builds the query.
  """

  @type id :: Ecto.UUID.t()

  @doc "The businesses the profile belongs or belonged to (its own membership rows)."
  @callback organization_ids(id()) :: [id()]

  @doc """
  The entry's rows for the person, each a map of column name to JSON value.
  `organization_id` is the business of a `:tenant` entry, `nil` otherwise.
  """
  @callback rows(map(), id(), id() | nil) :: [map()]
end
