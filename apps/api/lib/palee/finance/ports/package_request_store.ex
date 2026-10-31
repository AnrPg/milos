defmodule Palee.Finance.Ports.PackageRequestStore do
  @moduledoc """
  ADR-291: where packages waiting to be paid at the front desk are kept.
  Every call runs inside the caller's tenant scope (`Finance.with_tenant_context/2`).
  Requests are returned as plain maps.
  """

  @type request :: map()

  @doc """
  Creates a pending request, or returns the person's open one for that
  package. `params.today` (box-local) lets a pending request whose hold
  already ended be closed as `lapsed` and replaced.
  """
  @callback request(map()) :: {:ok, request(), :created | :existing} | {:error, term()}

  @callback get(Ecto.UUID.t()) :: request() | nil

  @doc "Pending requests held on or after `today`, oldest first; `user_id` narrows to one person."
  @callback list_open(Date.t(), keyword()) :: [request()]

  @doc "Closes a pending request (`cancelled`, `activated`, `lapsed`) under a row lock."
  @callback close(Ecto.UUID.t(), String.t(), map()) :: {:ok, request()} | {:error, term()}

  @doc "Closes as `lapsed` every pending request whose hold ended before `today`."
  @callback lapse_before(Date.t(), DateTime.t()) :: non_neg_integer()
end
