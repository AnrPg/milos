defmodule Palee.Organizations.Commands.SeedTenantDefaults do
  @moduledoc """
  ADR-133: runs the defaults another context seeds into a just-created
  organization (e.g. Workouts' default scale levels) inside the creation
  transaction, in the new organization's tenant scope.

  Organizations does not know what the defaults are: the orchestrating
  Application service passes a `seed_defaults` function
  `(%{organization_id, user_id} -> {:ok, term} | {:error, term})`. An error
  rolls the whole creation back.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext

  @doc "The seed used when a caller has no defaults to add."
  def none(_scope), do: {:ok, :none}

  def run(organization_id, user_id, seed_defaults) when is_function(seed_defaults, 1) do
    scope = %{organization_id: organization_id, user_id: user_id}
    RepoContext.run(scope, fn -> seed_defaults.(scope) end)
  end

  def seed_option(opts), do: Keyword.get(opts, :seed_defaults, &none/1)
end
