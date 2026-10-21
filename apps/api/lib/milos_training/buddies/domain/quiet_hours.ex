defmodule MilosTraining.Buddies.Domain.QuietHours do
  @moduledoc """
  Quiet hours (ADR-160 §2, board 15 Q7): a buddy's local window, e.g.
  23:00–07:00, crossing midnight or not. A request that arrives inside it
  is still delivered, silently (inbox, no push), and the sender is told
  «έχει ώρες ησυχίας».
  """

  @doc "Whether `now` falls in the quiet window `from`..`to` of zone `tz`."
  def quiet?(nil, _to, _tz, _now), do: false
  def quiet?(_from, nil, _tz, _now), do: false

  def quiet?(%Time{} = from, %Time{} = to, tz, %DateTime{} = now) do
    case DateTime.shift_zone(now, tz || "Etc/UTC") do
      {:ok, local} -> inside?(DateTime.to_time(local), from, to)
      {:error, _reason} -> inside?(DateTime.to_time(now), from, to)
    end
  end

  @doc "Whether the local time `time` is in `from`..`to` (end excluded)."
  def inside?(time, from, to) do
    if Time.compare(from, to) == :lt do
      Time.compare(time, from) != :lt and Time.compare(time, to) == :lt
    else
      Time.compare(time, from) != :lt or Time.compare(time, to) == :lt
    end
  end

  @doc "How a request reaches a buddy at `now`: silently inside their quiet hours."
  def delivery(hours, now) do
    case hours do
      %{quiet_from: from, quiet_to: to, tz: tz} -> %{silent: quiet?(from, to, tz, now)}
      _none -> %{silent: false}
    end
  end
end
