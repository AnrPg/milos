defmodule Palee.Application.GetFinancePackage do
  alias Palee.Application.PackageBranches
  alias Palee.Finance

  @doc "ADR-186 §8: a package valid only at other branches is not found."
  def call(context, id) do
    with %{} = package <- Finance.get_package(context, id),
         [_visible] <- PackageBranches.visible(context, [package]) do
      {:ok, %{package: package}}
    else
      _missing -> {:error, :not_found}
    end
  end

  def call(id) do
    case Finance.get_package(id) do
      nil -> {:error, :not_found}
      package -> {:ok, %{package: package}}
    end
  end
end
