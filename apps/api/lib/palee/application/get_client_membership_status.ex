defmodule Palee.Application.GetClientMembershipStatus do
  @moduledoc """
  A client's membership status for staff who may not see money (ADR-099):
  whether it is active or frozen, until when, which packages, and what is left
  of each allowance. No prices, invoices or payments.
  """

  alias Palee.Application.AuthorizeClientAccess
  alias Palee.Finance

  def call(context, client_user_id) do
    with :ok <- AuthorizeClientAccess.call(context, :view_membership_status, client_user_id) do
      {:ok, summarize(Finance.get_effective_entitlement(context, client_user_id))}
    end
  end

  defp summarize(nil), do: %{status: "none", packages: [], allowances: %{}}

  defp summarize(entitlement) do
    subscriptions =
      [Map.get(entitlement, :subscription) | Map.get(entitlement, :stacked_subscriptions, [])]
      |> Enum.reject(&is_nil/1)

    %{
      status: to_string(Map.get(entitlement, :status) || "none"),
      expires_on: Map.get(entitlement, :expires_on),
      frozen_until: Map.get(entitlement, :frozen_until),
      packages: subscriptions |> Enum.map(&Map.get(&1, :package_name)) |> Enum.reject(&is_nil/1),
      allowances:
        entitlement
        |> Map.get(:allowances, %{})
        |> Map.new(fn {key, allowance} ->
          {key, Map.take(allowance, [:limit, :remaining, :period_end])}
        end)
    }
  end
end
