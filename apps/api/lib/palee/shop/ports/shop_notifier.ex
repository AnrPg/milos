defmodule Palee.Shop.Ports.ShopNotifier do
  @moduledoc """
  How the shop tells people things (ADR-190): staff who look after the shop
  about low stock and new orders, a member that their order is ready. The
  adapter delivers through the Notifications context; notifications are a
  side effect and never undo the change that caused them.
  """

  @type context :: map()

  @doc "A variant's stock got worse (`low`, `critical`, `out`)."
  @callback stock_low(context(), map()) :: :ok

  @doc "A member placed an online order."
  @callback order_placed(context(), map()) :: :ok

  @doc "An order is ready for pickup (to the buyer)."
  @callback order_ready(context(), map()) :: :ok

  @doc "A ready order is still waiting to be collected (to the buyer)."
  @callback order_reminder(context(), map()) :: :ok

  @doc "The buyer's order was cancelled by staff or because its hold ran out (to the buyer)."
  @callback order_cancelled(context(), map()) :: :ok

  @doc "A variant the member asked about («Ειδοποίησέ με») is back in stock (to them)."
  @callback back_in_stock(context(), map()) :: :ok
end
