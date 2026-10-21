defmodule Palee.Application.UpdateFinancePackage do
  alias Palee.Finance

  def call(id, params), do: Finance.update_package(id, params)
end
