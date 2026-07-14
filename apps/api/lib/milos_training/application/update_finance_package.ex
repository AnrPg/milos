defmodule MilosTraining.Application.UpdateFinancePackage do
  alias MilosTraining.Finance

  def call(id, params), do: Finance.update_package(id, params)
end
