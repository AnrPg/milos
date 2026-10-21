defmodule Palee.Wellness.Domain.EntryKinds do
  @moduledoc "The wellness entry kinds and the module that owns each value (ADR-159 §1)."

  alias Palee.Wellness.Domain.{Meal, Sleep, Water}

  @kinds %{"water" => Water, "sleep" => Sleep, "meal" => Meal}
  @sources ~w(manual garmin apple_health health_connect)
  @device_sources @sources -- ["manual"]

  def kinds, do: @kinds |> Map.keys() |> Enum.sort()
  def sources, do: @sources
  def device_sources, do: @device_sources
  def known?(kind), do: is_map_key(@kinds, kind)

  def module(kind) do
    case Map.fetch(@kinds, kind) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_wellness_kind}
    end
  end

  @doc "Validates `params` as a value of `kind`."
  def cast(kind, params) when is_map(params) do
    with {:ok, module} <- module(kind) do
      case module.cast(params) do
        {:ok, value} -> {:ok, value}
        {:error, errors} -> {:error, {:invalid_wellness_value, errors}}
      end
    end
  end

  def cast(_kind, _params),
    do: {:error, {:invalid_wellness_value, %{"value" => "must be an object"}}}

  def counts_at(kind, value, occurred_at) do
    {:ok, module} = module(kind)
    module.counts_at(value, occurred_at)
  end
end
