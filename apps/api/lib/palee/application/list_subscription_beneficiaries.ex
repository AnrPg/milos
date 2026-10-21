defmodule Palee.Application.ListSubscriptionBeneficiaries do
  @moduledoc "People sharing a membership, with their nicknames (ADR-098)."

  alias Palee.{Finance, Identity}

  def call(context, subscription_id) do
    beneficiaries = Finance.list_beneficiaries(context, subscription_id)

    nicknames =
      beneficiaries
      |> Enum.map(& &1.user_id)
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1.nickname})

    Enum.map(beneficiaries, &Map.put(&1, :nickname, Map.get(nicknames, &1.user_id)))
  end
end
