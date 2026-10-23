defmodule Palee.Organizations.Ports.LocationScopeStore do
  @moduledoc "Persistence port of staff branch scopes (ADR-186)."

  @type context :: %{organization_id: binary()}

  @doc "The active (not archived) locations a membership is scoped to."
  @callback location_ids(context(), membership_id :: binary()) :: [binary()]

  @doc "The same for several memberships: `%{membership_id => [location_id]}`."
  @callback location_ids_by_membership(context(), membership_ids :: [binary()]) :: %{
              optional(binary()) => [binary()]
            }

  @doc "Replaces a membership's scope: `:all` or a list of location ids of the gym."
  @callback put_scope(context(), membership_id :: binary(), scope :: :all | [binary()]) ::
              {:ok, map()} | {:error, term()}
end
