defmodule Palee.AiUsage.AiUsageStore do
  @moduledoc false
  @behaviour Palee.AiUsage.Ports.AiUsageStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :ai_usage_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def insert_record(context, attrs), do: tenant_call(context, :insert_record, [attrs])

  @impl true
  def list_operation(context, operation_id),
    do: tenant_call(context, :list_operation, [operation_id])

  @impl true
  def summarize(context, params), do: tenant_call(context, :summarize, [params])

  @impl true
  def get_settings(context), do: tenant_call(context, :get_settings, [])

  @impl true
  def put_settings(context, changes), do: tenant_call(context, :put_settings, [changes])
end
