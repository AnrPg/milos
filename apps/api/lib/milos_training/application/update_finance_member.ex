defmodule MilosTraining.Application.UpdateFinanceMember do
  alias MilosTraining.{Finance, Identity}

  def call(user_id, params) do
    enriched = params |> string_key_map() |> maybe_put_user_type_snapshot(user_id)
    Finance.upsert_membership(user_id, enriched)
  end

  defp maybe_put_user_type_snapshot(params, user_id) do
    if Map.has_key?(params, "user_type_snapshot") do
      params
    else
      Map.put(params, "user_type_snapshot", derive_user_type(user_id))
    end
  end

  defp derive_user_type(user_id) do
    case Identity.find_by_id(user_id) do
      %{role: :athlete} -> "athlete"
      _ -> "member"
    end
  end

  defp string_key_map(params) when is_map(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end
end
