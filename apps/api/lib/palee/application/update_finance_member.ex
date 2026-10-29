defmodule Palee.Application.UpdateFinanceMember do
  @moduledoc """
  Creates or edits a person's finance profile in a gym. ADR-217: only clients
  (a member or athlete role in the gym) have one. Staff never get a profile,
  a package or a status, so they never reach the finance ledger or analytics;
  someone who is both staff and a client (a role they were explicitly given)
  is treated as the client they are. ADR-272: a guest of the box buys
  like a client, so a guest has one too.
  """

  alias Palee.{Finance, Organizations}

  def call(%{organization_id: _} = context, user_id, params) do
    case Organizations.buyer_role(context, user_id) do
      nil ->
        {:error, :not_a_client}

      client_role ->
        enriched =
          params
          |> string_key_map()
          |> Map.put_new("user_type_snapshot", Atom.to_string(client_role))

        Finance.upsert_membership(context, user_id, enriched)
    end
  end

  def call(_user_id, _params), do: {:error, :organization_context_required}

  defp string_key_map(params) when is_map(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end
end
