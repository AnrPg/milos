defmodule MilosTraining.Application.AssignFinanceMemberPackage do
  alias MilosTraining.Application.UpdateFinanceMember
  alias MilosTraining.Finance.Domain.PackageAssignmentPolicy
  alias MilosTraining.{Finance, Identity}

  def call(user_id, params) do
    with user when not is_nil(user) <- Identity.find_by_id(user_id),
         package_id when is_binary(package_id) <- package_id(params),
         package when not is_nil(package) <- Finance.get_package(package_id),
         :ok <- PackageAssignmentPolicy.can_assign?(package),
         {:ok, membership} <- ensure_membership(user.id, params) do
      Finance.assign_package(membership.id, package_id, params)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :bad_request}
    end
  end

  defp ensure_membership(user_id, params) do
    case Finance.get_member_profile(user_id) do
      %{membership: membership} ->
        {:ok, membership}

      nil ->
        UpdateFinanceMember.call(user_id, %{
          "status" => "trial",
          "signup_source" => signup_source(params)
        })
    end
  end

  defp package_id(params),
    do: params["membership_package_id"] || params[:membership_package_id]

  defp signup_source(params),
    do: params["signup_source"] || params[:signup_source] || "admin_created"
end
