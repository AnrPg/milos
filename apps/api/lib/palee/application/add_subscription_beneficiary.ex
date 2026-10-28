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

    # ADR-217: a beneficiary gets a finance profile, so they must be a client
    # (member or athlete) of the gym; staff-only people are refused.
    cond do
      user_id not in Organizations.list_active_membership_user_ids(organization_id) ->
        {:error, :not_found}

      is_nil(Organizations.client_role(organization_id, user_id)) ->
        {:error, :not_a_client}

      true ->
        Finance.add_beneficiary(context, subscription_id, user_id, admin_id, params)
    end
  end
end
