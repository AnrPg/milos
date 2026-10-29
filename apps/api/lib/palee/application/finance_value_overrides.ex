defmodule Palee.Application.FinanceValueOverrides do
  @moduledoc """
  ADR-274: staff set a value Palee works out (a member's status, a
  subscription's last day) by hand, put it back to automatic, and read the
  history. Every change keeps who made it, when, the automatic value it
  replaced and the value chosen; the screens show it on hover.
  """

  alias Palee.{Finance, Identity}

  @doc "Sets `field` for the member `user_id` (body: `value`, `reason`, `subscription_id`)."
  def set(%{user_id: actor_id} = context, user_id, field, params) when is_map(params) do
    params = stringify(params)

    with {:ok, override} <-
           Finance.set_value_override(
             context,
             user_id,
             field,
             Map.put(params, "actor_id", actor_id)
           ) do
      {:ok, with_names(override)}
    end
  end

  @doc "Puts `field` back to Palee's own value."
  def reset(%{user_id: actor_id} = context, user_id, field, params) when is_map(params) do
    params = stringify(params)

    with {:ok, override} <-
           Finance.reset_value_override(
             context,
             user_id,
             field,
             Map.put(params, "actor_id", actor_id)
           ) do
      {:ok, with_names(override)}
    end
  end

  @doc "Every value set by hand for the member, newest first."
  def history(context, user_id) do
    overrides = Finance.list_value_overrides(context, user_id)
    names = names(overrides)
    {:ok, Enum.map(overrides, &put_names(&1, names))}
  end

  @doc "Adds the names of the people who set or ended overrides."
  def with_names(override) when is_map(override), do: put_names(override, names([override]))

  def with_names(overrides) when is_list(overrides) do
    names = names(overrides)
    Enum.map(overrides, &put_names(&1, names))
  end

  defp names(overrides) do
    overrides
    |> Enum.flat_map(&[&1.set_by_id, &1.ended_by_id])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Identity.list_by_ids()
    |> Map.new(&{&1.id, &1.nickname})
  end

  defp put_names(override, names) do
    override
    |> Map.put(:set_by_name, Map.get(names, override.set_by_id))
    |> Map.put(:ended_by_name, Map.get(names, override.ended_by_id))
  end

  defp stringify(params), do: Map.new(params, fn {key, value} -> {to_string(key), value} end)
end
