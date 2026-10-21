defmodule Palee.Application.GetFinancePackage do
  alias Palee.Finance

  def call(id) do
    case Finance.get_package(id) do
      nil -> {:error, :not_found}
      package -> {:ok, %{package: package}}
    end
  end
end
