defmodule Palee.Application.RecordCommunicationMessage do
  alias Palee.Analytics

  def call(attrs) when is_map(attrs) do
    params = string_key_map(attrs)

    :telemetry.execute(
      [:palee, :communication, :message_recorded],
      %{count: 1},
      params
    )

    case Analytics.record_communication_message(params) do
      {:ok, _message} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def call_unsafe(attrs) do
    case call(attrs) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp string_key_map(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end
end
