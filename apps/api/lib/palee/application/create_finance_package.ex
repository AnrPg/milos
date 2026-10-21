defmodule Palee.Application.CreateFinancePackage do
  alias Palee.Finance

  def call(params), do: Finance.create_package(params)
end
