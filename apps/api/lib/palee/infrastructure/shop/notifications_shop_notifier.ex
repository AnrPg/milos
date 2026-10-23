defmodule Palee.Infrastructure.Shop.NotificationsShopNotifier do
  @moduledoc """
  `Shop.Ports.ShopNotifier` over the Notifications context (ADR-190). Staff
  alerts go to everyone holding `manage_shop` except the person who made the
  change; ready-for-pickup goes to the buyer. Failures are logged and
  swallowed: a notification never undoes a sale.
  """

  @behaviour Palee.Shop.Ports.ShopNotifier

  require Logger

  alias Palee.{Notifications, Organizations}

  @impl true
  def stock_low(context, payload), do: to_staff(context, "shop_stock_low", payload)

  @impl true
  def order_placed(context, payload), do: to_staff(context, "shop_order_placed", payload)

  @impl true
  def order_ready(context, payload), do: to_buyer(context, "shop_order_ready", payload)

  @impl true
  def order_reminder(context, payload), do: to_buyer(context, "shop_order_reminder", payload)

  @impl true
  def order_cancelled(context, payload), do: to_buyer(context, "shop_order_cancelled", payload)

  @impl true
  def back_in_stock(context, payload), do: to_buyer(context, "shop_back_in_stock", payload)

  defp to_buyer(context, type, %{user_id: user_id} = payload) when is_binary(user_id),
    do: deliver(type, Map.put(payload, :organization_id, context.organization_id))

  defp to_buyer(_context, _type, _payload), do: :ok

  defp to_staff(context, type, payload) do
    context.organization_id
    |> Organizations.list_user_ids_with_capability(:manage_shop)
    |> Enum.reject(&(&1 == Map.get(context, :user_id)))
    |> Enum.each(fn user_id ->
      deliver(
        type,
        Map.merge(payload, %{user_id: user_id, organization_id: context.organization_id})
      )
    end)
  end

  defp deliver(type, payload) do
    Notifications.process_event(type, payload)
    :ok
  rescue
    error ->
      Logger.warning("shop_notification_failed type=#{type} reason=#{Exception.message(error)}")
      :ok
  end
end
