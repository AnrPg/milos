defmodule MilosTraining.Application.ListFinancePackages do
  alias MilosTraining.Finance

  def call, do: {:ok, %{packages: Finance.list_packages()}}
end
