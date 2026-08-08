defmodule MilosTraining.Application.UpdateFinanceMember do
  alias MilosTraining.{Finance, Organizations}

  def call(context, user_id, params) do
    enriched = params |> string_key_map() |> maybe_put_user_type_snapshot(context, user_id)
    Finance.upsert_membership(context, user_id, enriched)
  end

  def call(_user_id, _params), do: {:error, :organization_context_required}

  defp maybe_put_user_type_snapshot(params, context, user_id) do
    if Map.has_key?(params, "user_type_snapshot") do
      params
    else
      Map.put(params, "user_type_snapshot", derive_user_type(context, user_id))
    end
  end

  defp derive_user_type(%{organization_id: organization_id}, user_id) do
    case Enum.find(Organizations.list_memberships(user_id), fn %{
                                                                 membership: membership,
                                                                 organization: organization
                                                               } ->
           organization.id == organization_id and membership.status == :active
         end) do
      %{membership: %{role: :athlete}} -> "athlete"
      _ -> "member"
    end
  end

  defp string_key_map(params) when is_map(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end
end
