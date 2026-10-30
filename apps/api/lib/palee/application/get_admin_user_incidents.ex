defmodule Palee.Application.GetAdminUserIncidents do
  @moduledoc """
  A member's injuries on their staff profile (ADR-286): every report the gym
  keeps (`admin_only` ones too) and the member's own reports they share with
  their boxes. The controller checks `view_health` for this client; the read
  is logged for the member.
  """

  alias Palee.Application.StaffInjuryAccess
  alias Palee.{Identity, Wellbeing}

  def call(context, user_id) do
    with %{} <- Identity.find_by_id(user_id) || {:error, :not_found} do
      reports =
        Wellbeing.with_tenant_context(context, fn ->
          reports = Wellbeing.list_box_injuries_for_user(user_id)
          if reports != [], do: StaffInjuryAccess.log_reads(context, "profile", reports)
          reports
        end)

      incidents = Enum.map(reports, &serialize/1)

      {:ok,
       %{
         user_id: user_id,
         incidents: incidents,
         summary: %{
           total: length(incidents),
           active: Enum.count(incidents, &(&1.status == "active"))
         }
       }}
    end
  end

  defp serialize(report) do
    report
    |> Map.put(:owned_by_member, StaffInjuryAccess.owned_by_member?(report))
    |> Map.take([
      :owned_by_member,
      :id,
      :body_area,
      :severity,
      :status,
      :started_on,
      :healed_on,
      :description,
      :training_limitations,
      :tags,
      :visibility,
      :reported_by_role,
      :inserted_at
    ])
  end
end
