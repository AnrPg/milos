defmodule Palee.FlakyProviderToday do
  @moduledoc """
  A `Ports.ProviderToday` for tests: providers whose id is stored under
  `:failing_today_providers` raise; the rest answer as in production.
  """

  @behaviour Palee.Application.Ports.ProviderToday

  alias Palee.Application.ProviderTodayItems

  @impl true
  def items(tenant, user_id, date, timezone) do
    if tenant.organization_id in Application.get_env(
         :palee,
         :failing_today_providers,
         []
       ),
       do: raise("provider down"),
       else: ProviderTodayItems.items(tenant, user_id, date, timezone)
  end
end
