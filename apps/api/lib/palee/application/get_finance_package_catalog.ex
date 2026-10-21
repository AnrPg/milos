defmodule Palee.Application.GetFinancePackageCatalog do
  alias Palee.Finance

  def call, do: {:ok, Finance.get_package_catalog()}
end
