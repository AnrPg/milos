defmodule Palee.Application.ListFinancePackages do
  alias Palee.Finance

  def call, do: {:ok, %{packages: Finance.list_packages()}}
end
