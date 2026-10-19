defmodule MilosTraining.Application.SweepOrphanMedia do
  @moduledoc """
  ADR-148: deletes uploads nobody attached within a day (abandoned editors,
  failed posts), gym by gym and person by person, each in its own scope.
  """

  alias MilosTraining.Application.ReleaseMedia
  alias MilosTraining.{Media, Organizations}

  def call(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -Media.orphan_after_seconds())

    tenant =
      for %{organization: organization} <- Organizations.list_active_organizations_for_system() do
        sweep(%{organization_id: organization.id}, :tenant, cutoff)
      end

    account =
      for user_id <- Media.account_orphan_owner_ids(cutoff) do
        sweep(%{user_id: user_id}, :account, cutoff)
      end

    {:ok, Enum.sum(tenant) + Enum.sum(account)}
  end

  defp sweep(context, scope, cutoff) do
    ids = context |> Media.list_unattached(scope, cutoff) |> Enum.map(& &1.id)
    :ok = ReleaseMedia.call(context, scope, ids)
    length(ids)
  end
end
