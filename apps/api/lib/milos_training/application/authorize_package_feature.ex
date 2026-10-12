defmodule MilosTraining.Application.AuthorizePackageFeature do
  @moduledoc """
  Gate for unmetered Phase C features (ADR-098): the client's packages must
  include the capability. Staff are never gated.
  """

  alias MilosTraining.Application.AuthorizeFinanceEntitlement

  @staff_roles [:owner, :admin, :coach]

  def call(%{role: role}, _actor, _capability) when role in @staff_roles, do: :ok

  def call(context, actor, capability) do
    case AuthorizeFinanceEntitlement.call(context, actor, %{capability: capability}) do
      :ok -> :ok
      {:ok, _decision} -> :ok
      {:error, reason, _details} -> {:error, reason}
      error -> error
    end
  end
end
