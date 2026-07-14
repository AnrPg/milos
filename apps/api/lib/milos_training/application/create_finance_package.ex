defmodule MilosTraining.Application.CreateFinancePackage do
  alias MilosTraining.Finance

  def call(params), do: Finance.create_package(params)
end
