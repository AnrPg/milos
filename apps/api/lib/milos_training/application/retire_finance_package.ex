defmodule MilosTraining.Application.RetireFinancePackage do
  alias MilosTraining.Finance

  def call(package_id, params) do
    replacements =
      params["replacement_package_by_role"] || params[:replacement_package_by_role] || %{}

    Finance.retire_package(package_id, replacements)
  end
end
