defmodule MilosTraining.Application.AuthorizePackageFeature do
  @moduledoc """
  Gate for unmetered Phase C features (ADR-098): the client's packages must
  include the capability. Staff are never gated.
  """

  alias MilosTraining.Application.AuthorizeFinanceEntitlement
  alias MilosTraining.Organizations

  def call(context, actor, capability) do
    if Organizations.any_role?(context, Organizations.admin_roles()),
      do: :ok,
      else: authorize(context, actor, capability)
  end

  defp authorize(context, actor, capability) do
    case AuthorizeFinanceEntitlement.call(context, actor, %{capability: capability}) do
      :ok -> :ok
      {:ok, _decision} -> :ok
      {:error, reason, _details} -> {:error, reason}
      error -> error
    end
  end
end
