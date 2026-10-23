defmodule Palee.Workers.ShopOrderSweepJob do
  @moduledoc """
  Every hour, for each business (ADR-190): releases unpaid online orders
  whose hold ran out (their buyers are told, `shop_order_cancelled`) and
  reminds buyers of orders waiting for pickup (`shop_order_reminder`).
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 1_800]

  require Logger

  alias Palee.Application.Shop.Fulfilment
  alias Palee.Organizations

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()

    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} ->
      context = %{organization_id: organization.id, user_id: nil}

      try do
        Fulfilment.expire_unpaid(context, now)
        Fulfilment.send_pickup_reminders(context, now)
      rescue
        error ->
          Logger.warning(
            "shop_order_sweep_failed organization=#{organization.id} reason=#{Exception.message(error)}"
          )
      end
    end)

    :ok
  end
end
