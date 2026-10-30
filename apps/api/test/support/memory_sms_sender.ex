defmodule Palee.TestSupport.MemorySmsSender do
  @moduledoc """
  In-memory `SmsSender` for tests (ADR-280 §3): keeps every message sent,
  newest first, in a globally named Agent. Tests read the messages of their
  own freshly generated numbers, so async tests do not collide. A number
  put in `fail_for/1` answers `{:error, :sms_unavailable}`.
  """

  @behaviour Palee.Application.Ports.SmsSender

  def start do
    case Agent.start(fn -> %{sent: [], failing: MapSet.new()} end, name: __MODULE__) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end

  @impl true
  def deliver(%{to: to} = message) do
    {:ok, _pid} = start()

    Agent.get_and_update(__MODULE__, fn state ->
      if MapSet.member?(state.failing, to),
        do: {{:error, :sms_unavailable}, state},
        else: {:ok, %{state | sent: [message | state.sent]}}
    end)
  end

  @doc "Messages sent to `to`, newest first."
  def sent_to(to) do
    {:ok, _pid} = start()
    Agent.get(__MODULE__, fn state -> Enum.filter(state.sent, &(&1.to == to)) end)
  end

  @doc "The 6-digit code of the latest message to `to` (nil if none)."
  def last_code(to) do
    case sent_to(to) do
      [%{body: body} | _rest] ->
        case Regex.run(~r/\b(\d{6})\b/, body) do
          [_match, code] -> code
          nil -> nil
        end

      [] ->
        nil
    end
  end

  @doc "Makes every send to `to` fail."
  def fail_for(to) do
    {:ok, _pid} = start()
    Agent.update(__MODULE__, &%{&1 | failing: MapSet.put(&1.failing, to)})
  end
end
