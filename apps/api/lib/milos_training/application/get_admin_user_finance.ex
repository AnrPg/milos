defmodule MilosTraining.Application.GetAdminUserFinance do
  @moduledoc false

  alias MilosTraining.Application.GetFinanceMemberProfile
  alias MilosTraining.Identity
  alias MilosTraining.Identity.Domain.AdminProfilePolicy

  def call(user_id) do
    with %{} = user <- Identity.find_by_id(user_id) || {:error, :not_found} do
      if AdminProfilePolicy.finance_available?(user.role) do
        with {:ok, profile} <- GetFinanceMemberProfile.call(user_id) do
          {:ok,
           %{
             user_id: user_id,
             available: true,
             summary: %{
               credit_balance: profile.credit_balance,
               current_status: profile.drill_down.current_status,
               package_relationship: profile.drill_down.package_relationship,
               outstanding_items: profile.drill_down.outstanding_items
             },
             drill_down: profile.drill_down,
             operational_links: %{
               workspace: "/admin/finance",
               member: "/admin/finance?member=#{user_id}"
             }
           }}
        end
      else
        {:ok,
         %{
           user_id: user_id,
           available: false,
           summary: nil,
           drill_down: nil,
           operational_links: %{}
         }}
      end
    end
  end
end
