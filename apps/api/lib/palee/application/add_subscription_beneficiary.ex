defmodule Palee.Application.AddSubscriptionBeneficiary do
  @moduledoc "Adds a gym member as a beneficiary of a shared membership (ADR-098)."

  alias Palee.{Finance, Organizations}

  def call(
        %{organization_id: organization_id} = context,
        %{id: admin_id},
        subscription_id,
        params
      ) do
    user_id = Map.get(params, :user_id) || Map.get(params, "user_id")

    if user_id in Organizations.list_active_membership_user_ids(organization_id),
      do: Finance.add_beneficiary(context, subscription_id, user_id, admin_id, params),
      else: {:error, :not_found}
  end
end
