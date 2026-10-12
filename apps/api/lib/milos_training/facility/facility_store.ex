defmodule MilosTraining.Facility.FacilityStore do
  @moduledoc false
  @behaviour MilosTraining.Facility.Ports.FacilityStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :facility_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def list_locations(context, opts), do: tenant_call(context, :list_locations, [opts])

  @impl true
  def get_location(context, id), do: tenant_call(context, :get_location, [id])

  @impl true
  def create_location(context, params), do: tenant_call(context, :create_location, [params])

  @impl true
  def update_location(context, id, params),
    do: tenant_call(context, :update_location, [id, params])

  @impl true
  def archive_location(context, id), do: tenant_call(context, :archive_location, [id])

  @impl true
  def get_check_in(context, user_id, date),
    do: tenant_call(context, :get_check_in, [user_id, date])

  @impl true
  def create_check_in(context, attrs), do: tenant_call(context, :create_check_in, [attrs])

  @impl true
  def list_check_ins(context, filters), do: tenant_call(context, :list_check_ins, [filters])
end
