defmodule MilosTraining.Notifications.Domain.PayloadNormalizer do
  def normalize(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {
        if(is_atom(key), do: Atom.to_string(key), else: key),
        normalize_value(value)
      }
    end)
  end

  defp normalize_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp normalize_value(%Date{} = value), do: Date.to_iso8601(value)
  defp normalize_value(%Time{} = value), do: Time.to_iso8601(value)
  defp normalize_value(value) when is_map(value), do: normalize(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(value), do: value
end
