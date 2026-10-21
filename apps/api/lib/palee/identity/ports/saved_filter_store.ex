defmodule Palee.Identity.Ports.SavedFilterStore do
  @moduledoc "Persistence port of remembered filters (ADR-151); every call is the context user's own."

  @callback list(context :: map(), surface :: String.t()) :: [map()]
  @callback put_last_used(context :: map(), surface :: String.t(), params :: map(), DateTime.t()) ::
              {:ok, map()}
  @callback put_named(
              context :: map(),
              surface :: String.t(),
              name :: String.t(),
              params :: map(),
              DateTime.t()
            ) ::
              {:ok, map()} | {:error, term()}
  @callback count_named(context :: map(), surface :: String.t()) :: non_neg_integer()
  @callback delete_named(context :: map(), id :: binary()) :: :ok | {:error, :not_found}

  # ADR-154: alerts of named Γύρω μου filters.
  @callback set_alert(context :: map(), id :: binary(), enabled :: boolean(), DateTime.t()) ::
              {:ok, map()} | {:error, :not_found}
  @doc "Filters whose alert is due on `day`, across people (a definer lookup)."
  @callback alert_candidates(day :: Date.t(), limit :: pos_integer()) :: [
              %{id: binary(), user_id: binary()}
            ]
  @doc "Claims `day` for the filter's alert; `since` is when it last looked."
  @callback claim_alert(context :: map(), id :: binary(), day :: Date.t()) ::
              {:ok, %{id: binary(), name: String.t(), params: map(), since: DateTime.t()}}
              | {:error, :taken}
  @callback finish_alert(context :: map(), id :: binary(), DateTime.t()) :: :ok
end
