defmodule Palee.Application.MyToday do
  @moduledoc """
  `GET /api/me/today` (ADR-162; board 17, Q2): the «Σήμερα» card on every
  Box, today's items from all the member's active providers in time order
  (booked classes, appointments, the coach's programme, the WOD), each with
  its source label and the provider to switch to when tapped.

  Each provider is asked in its own tenant context with the member's own
  authorization there (`Ports.ProviderToday`); the answers are merged here.
  A provider that fails is skipped and listed in `failed_organization_ids`,
  and the card is marked `partial`, so one provider never breaks the rest.
  """

  require Logger

  alias Palee.Application.MyProviders
  alias Palee.Organizations
  alias Palee.Organizations.Domain.ProviderToday

  def call(context, params, now \\ DateTime.utc_now()) do
    with {:ok, timezone} <- timezone(param(params, "timezone")),
         {:ok, date} <- date(param(params, "date"), timezone, now) do
      {active, _former} =
        context |> Organizations.list_my_providers() |> Organizations.split_providers()

      merged =
        active
        |> Enum.map(&{&1.organization_id, provider_items(context, &1, date, timezone)})
        |> ProviderToday.merge()

      {:ok,
       %{
         date: date,
         timezone: timezone,
         items: merged.items,
         partial: merged.partial,
         failed_organization_ids: merged.failed
       }}
    end
  end

  defp provider_items(context, provider, date, timezone) do
    with {:ok, tenant} <- MyProviders.tenant_context(context, provider.organization_id),
         {:ok, items} <- impl().items(tenant, context.user_id, date, timezone) do
      {:ok, Enum.map(items, &label(&1, provider))}
    else
      {:error, reason} -> failed(provider, reason)
      other -> failed(provider, other)
    end
  rescue
    error -> failed(provider, error)
  end

  defp label(item, provider) do
    Map.merge(item, %{
      source: %{
        kind: "organization",
        organization_id: provider.organization_id,
        name: provider.name,
        former: false
      },
      target: %{organization_id: provider.organization_id, slug: provider.slug}
    })
  end

  defp failed(provider, reason) do
    Logger.warning(
      "today items failed organization_id=#{provider.organization_id} reason=#{inspect(reason)}"
    )

    {:error, :provider_failed}
  end

  defp timezone(nil), do: {:ok, "Etc/UTC"}
  defp timezone(""), do: {:ok, "Etc/UTC"}

  defp timezone(timezone) when is_binary(timezone) do
    case DateTime.now(timezone) do
      {:ok, _now} -> {:ok, timezone}
      _invalid -> {:error, :invalid_timezone}
    end
  end

  defp timezone(_timezone), do: {:error, :invalid_timezone}

  defp date(nil, timezone, now),
    do: {:ok, now |> DateTime.shift_zone!(timezone) |> DateTime.to_date()}

  defp date(value, _timezone, _now) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _invalid -> {:error, :invalid_date}
    end
  end

  defp date(_value, _timezone, _now), do: {:error, :invalid_date}

  defp impl,
    do:
      Application.get_env(
        :palee,
        :provider_today,
        Palee.Application.ProviderTodayItems
      )

  defp param(params, key), do: Map.get(params, key) || Map.get(params, String.to_atom(key))
end
