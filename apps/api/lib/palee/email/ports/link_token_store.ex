defmodule Palee.Email.Ports.LinkTokenStore do
  @moduledoc """
  Persistence port of single-use email links (ADR-203). Only token hashes
  cross it.
  """

  alias Palee.Email.LinkToken

  @doc """
  Inserts a link; with `replace_previous: true` the login's unused links of
  the same purpose are deleted in the same transaction.
  """
  @callback insert(map(), keyword()) :: {:ok, LinkToken.t()} | {:error, term()}

  @doc """
  Marks the link used at `now`, only when it is unused and unexpired, in
  one statement (`UPDATE ... RETURNING`), so two racing requests cannot
  both consume it. `nil` when nothing matched.
  """
  @callback consume(String.t(), binary(), DateTime.t()) :: LinkToken.t() | nil

  @callback get_by_hash(String.t(), binary()) :: LinkToken.t() | nil
end
