defmodule MilosTraining.Application.GetFinancePackageCatalog do
  alias MilosTraining.Finance

  def call, do: {:ok, Finance.get_package_catalog()}
end
