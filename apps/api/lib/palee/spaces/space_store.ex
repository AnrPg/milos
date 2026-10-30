defmodule Palee.Spaces.SpaceStore do
  @moduledoc false
  @behaviour Palee.Spaces.Ports.SpaceStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :space_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def list_spaces(context, filters), do: tenant_call(context, :list_spaces, [filters])
  @impl true
  def get_space(context, id), do: tenant_call(context, :get_space, [id])
  @impl true
  def save_space(context, id, attrs), do: tenant_call(context, :save_space, [id, attrs])
  @impl true
  def list_floor_plans(context, filters), do: tenant_call(context, :list_floor_plans, [filters])
  @impl true
  def get_floor_plan(context, id), do: tenant_call(context, :get_floor_plan, [id])
  @impl true
  def save_floor_plan(context, id, attrs),
    do: tenant_call(context, :save_floor_plan, [id, attrs])

  @impl true
  def delete_floor_plan(context, id), do: tenant_call(context, :delete_floor_plan, [id])

  @impl true
  def list_unavailabilities(context, space_ids, from),
    do: tenant_call(context, :list_unavailabilities, [space_ids, from])

  @impl true
  def create_unavailability(context, attrs),
    do: tenant_call(context, :create_unavailability, [attrs])

  @impl true
  def delete_unavailability(context, space_id, id),
    do: tenant_call(context, :delete_unavailability, [space_id, id])

  @impl true
  def get_settings(context), do: tenant_call(context, :get_settings, [])
  @impl true
  def put_settings(context, attrs), do: tenant_call(context, :put_settings, [attrs])
  @impl true
  def list_photos(context, kind, filters), do: tenant_call(context, :list_photos, [kind, filters])
  @impl true
  def get_photo(context, kind, id), do: tenant_call(context, :get_photo, [kind, id])
  @impl true
  def save_photo(context, kind, id, attrs),
    do: tenant_call(context, :save_photo, [kind, id, attrs])

  @impl true
  def delete_photo(context, kind, id), do: tenant_call(context, :delete_photo, [kind, id])
  @impl true
  def order_photos(context, kind, order), do: tenant_call(context, :order_photos, [kind, order])
end
