defmodule Palee.Application.MyProviders do
  @moduledoc """
  Box ▾ (ADR-162; board 17, Q1): everyone who provides the member's
  training, a gym or an independent coach, with what the sheet shows for
  each (kind, logo, next booking or session, unread coach messages), the
  former providers («Παλιοί πάροχοι», Q6), and the provider Box opens on,
  remembered on the account. With one provider the client hides ▾.

  Each provider's live facts are read in that provider's own tenant context
  as the member (their authorization there); one provider failing leaves
  its facts empty and marks the provider `partial`, never the whole list.
  """

  require Logger

  alias Palee.{Appointments, Messaging, Organizations, Scheduling}

  @horizon_days 30

  def call(context, now \\ DateTime.utc_now()) do
    providers = Organizations.list_my_providers(context)
    {active, former} = Organizations.split_providers(providers)

    selected =
      Organizations.selected_provider(active, Organizations.get_provider_selection(context))

    {:ok,
     %{
       selected_organization_id: selected,
       providers: Enum.map(active, &active_view(context, &1, selected, now)),
       former: Enum.map(former, &former_view/1)
     }}
  end

  @doc "`PUT /api/me/providers/selected`: remembers the provider Box opens on."
  def select(context, organization_id) do
    {active, _former} =
      context |> Organizations.list_my_providers() |> Organizations.split_providers()

    if is_binary(organization_id) and Enum.any?(active, &(&1.organization_id == organization_id)) do
      :ok = Organizations.put_provider_selection(context, organization_id)
      call(context)
    else
      {:error, :unknown_provider}
    end
  end

  @doc "The member's tenant context at one provider (their own authorization)."
  def tenant_context(%{account: account}, organization_id) when not is_nil(account),
    do: Organizations.resolve_tenant_context_by_id(account, organization_id)

  def tenant_context(_context, _organization_id), do: {:error, :account_required}

  defp active_view(context, provider, selected, now) do
    facts = facts(context, provider, now)

    provider
    |> Map.take([:organization_id, :name, :slug, :kind, :logo_url, :primary_color, :roles])
    |> Map.merge(%{
      selected: provider.organization_id == selected,
      next: facts.next,
      unread_messages: facts.unread,
      partial: facts.partial
    })
  end

  defp former_view(provider),
    do:
      Map.take(provider, [
        :organization_id,
        :name,
        :slug,
        :kind,
        :logo_url,
        :primary_color,
        :ended_at
      ])

  defp facts(context, provider, now) do
    with {:ok, tenant} <- tenant_context(context, provider.organization_id) do
      %{
        next: next(tenant, context.user_id, now),
        unread: unread(tenant, context.user_id),
        partial: false
      }
    else
      _error -> %{next: nil, unread: 0, partial: true}
    end
  rescue
    error ->
      Logger.warning(
        "provider facts failed organization_id=#{provider.organization_id} error=#{inspect(error)}"
      )

      %{next: nil, unread: 0, partial: true}
  end

  defp next(tenant, user_id, now) do
    until = DateTime.add(now, @horizon_days * 86_400, :second)

    class =
      tenant
      |> Scheduling.list_member_slots(user_id, now, until)
      |> List.first()
      |> case do
        nil -> nil
        slot -> %{kind: "class", at: slot.scheduled_at, title: slot_title(slot), id: slot.id}
      end

    appointment =
      tenant
      |> Appointments.list_bookings(%{user_id: user_id})
      |> Enum.filter(&(&1.status == "booked" and is_nil(&1.slot.cancelled_at)))
      |> Enum.filter(&(DateTime.compare(&1.slot.starts_at, now) == :gt))
      |> Enum.min_by(& &1.slot.starts_at, DateTime, fn -> nil end)
      |> case do
        nil -> nil
        booking -> %{kind: "appointment", at: booking.slot.starts_at, title: nil, id: booking.id}
      end

    [class, appointment]
    |> Enum.reject(&is_nil/1)
    |> Enum.min_by(& &1.at, DateTime, fn -> nil end)
  end

  defp unread(tenant, user_id),
    do: Messaging.with_tenant_context(tenant, fn -> Messaging.count_unread_threads(user_id) end)

  @doc false
  def slot_title(slot), do: slot.name || (slot.class_type && slot.class_type.name)
end
