defmodule Palee.BoxScreens.BoxScreenStore do
  @moduledoc false
  @behaviour Palee.BoxScreens.Ports.BoxScreenStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :box_screen_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def list(context), do: tenant_call(context, :list, [])
  @impl true
  def count(context), do: tenant_call(context, :count, [])
  @impl true
  def get(context, id), do: tenant_call(context, :get, [id])
  @impl true
  def insert(context, attrs), do: tenant_call(context, :insert, [attrs])
  @impl true
  def update(context, id, attrs), do: tenant_call(context, :update, [id, attrs])
  @impl true
  def delete(context, id), do: tenant_call(context, :delete, [id])

  # Outside any tenant: the code names the box (SECURITY DEFINER lookup).
  @impl true
  def find_pairing(hash, now), do: adapter().find_pairing(hash, now)

  @impl true
  def claim(context, id, hash, now), do: tenant_call(context, :claim, [id, hash, now])
  @impl true
  def touch(context, id, now), do: tenant_call(context, :touch, [id, now])
end
