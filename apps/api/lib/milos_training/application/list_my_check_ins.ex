defmodule MilosTraining.Application.ListMyCheckIns do
  @moduledoc """
  The member's Πώς νιώθω timeline (ADR-140 §2): the question catalog and
  every submission in `[from, to)` (default: the last 30 days), oldest first.
  """

  alias MilosTraining.Wellbeing

  @default_days 30
  @max_days 366

  def call(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    with {:ok, from, to} <- window(params, now) do
      check_ins =
        Wellbeing.with_tenant_context(context, fn ->
          Wellbeing.list_check_ins_between(user_id, from, to)
        end)

      {:ok, %{questions: Wellbeing.check_in_questions(), check_ins: check_ins}}
    end
  end

  defp window(params, now) do
    with {:ok, to} <- parse(params["to"], now),
         {:ok, from} <- parse(params["from"], DateTime.add(to, -@default_days * 86_400, :second)) do
      cond do
        DateTime.compare(from, to) != :lt -> {:error, :invalid_range}
        DateTime.diff(to, from, :second) > @max_days * 86_400 -> {:error, :invalid_range}
        true -> {:ok, from, to}
      end
    end
  end

  defp parse(nil, default), do: {:ok, default}
  defp parse("", default), do: {:ok, default}

  defp parse(value, _default) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> {:error, :invalid_range}
    end
  end

  defp parse(_value, _default), do: {:error, :invalid_range}
end
