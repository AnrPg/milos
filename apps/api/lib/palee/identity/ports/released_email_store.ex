defmodule Palee.Identity.Ports.ReleasedEmailStore do
  @moduledoc "ADR-211: addresses held for the login that moved away from them."

  @type id :: Ecto.UUID.t()

  @doc "Holds `email` for `login_id` until `until` (a later release of the same address replaces it)."
  @callback reserve(String.t(), id(), DateTime.t(), DateTime.t()) :: :ok

  @doc "Whether `email` is held at `now` for a login other than `login_id` (nil: for any login)."
  @callback reserved_for_other?(String.t(), id() | nil, DateTime.t()) :: boolean()

  @doc "Ends the hold of `login_id` on `email` (it took the address back)."
  @callback release(String.t(), id()) :: :ok
end
