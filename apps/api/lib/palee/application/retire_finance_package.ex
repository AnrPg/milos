defmodule Palee.Application.RetireFinancePackage do
  alias Palee.Application.PackageBranches
  alias Palee.Finance

  @doc "ADR-186 §8: only a package valid inside the acting branches retires."
  def call(context, package_id, params) do
    with :ok <- PackageBranches.authorize_change(context, package_id, %{}) do
      replacements =
        params["replacement_package_by_role"] || params[:replacement_package_by_role] || %{}

      Finance.retire_package(context, package_id, replacements)
    end
  end

  def call(package_id, params) do
    replacements =
      params["replacement_package_by_role"] || params[:replacement_package_by_role] || %{}

    Finance.retire_package(package_id, replacements)
  end
end
