defmodule MilosTraining.Buddies.Domain.SettingsPolicy do
  @moduledoc """
  A person's buddy settings (ADR-160 §1, board 15 Q7): quiet hours, local
  to their zone, when requests still arrive but silently and the sender is
  told; and whether their buddies may see their phone for «Πάρε με
  τηλέφωνο» (off by default).
  """

  @default_tz "Europe/Athens"
  @phone ~r/^\+?[0-9 ()-]{6,24}$/

  def default_tz, do: @default_tz

  def defaults,
    do: %{quiet_from: nil, quiet_to: nil, tz: @default_tz, share_phone: false, phone: nil}

  @doc "The person's settings with every default filled."
  def effective(nil), do: defaults()

  def effective(settings) do
    Map.merge(defaults(), Map.take(settings, [:quiet_from, :quiet_to, :tz, :share_phone, :phone]))
  end

  @doc """
  The fields to write from `params` over `current`. `quiet_hours` is
  `%{"from" => "23:00", "to" => "07:00"}` or null to turn them off; `tz` is
  an IANA zone (checked with `valid_zone?`); sharing the phone needs one.
  """
  def changes(current, params, valid_zone?) when is_function(valid_zone?, 1) do
    current = effective(current)

    with {:ok, quiet} <- quiet(params, current),
         {:ok, tz} <- tz(params, current, valid_zone?),
         {:ok, phone} <- phone(params, current),
         {:ok, share} <- share(params, current, phone) do
      {:ok, Map.merge(quiet, %{tz: tz, phone: phone, share_phone: share})}
    end
  end

  defp quiet(params, current) do
    case fetch(params, "quiet_hours") do
      :missing ->
        {:ok, %{quiet_from: current.quiet_from, quiet_to: current.quiet_to}}

      {:ok, nil} ->
        {:ok, %{quiet_from: nil, quiet_to: nil}}

      {:ok, %{} = hours} ->
        with {:ok, from} <- time(get(hours, "from")),
             {:ok, to} <- time(get(hours, "to")) do
          if Time.compare(from, to) == :eq,
            do: {:error, :invalid_quiet_hours},
            else: {:ok, %{quiet_from: from, quiet_to: to}}
        end

      _other ->
        {:error, :invalid_quiet_hours}
    end
  end

  defp time(%Time{} = time), do: {:ok, %{time | second: 0, microsecond: {0, 0}}}

  defp time(value) when is_binary(value) do
    case Regex.run(~r/^([01]\d|2[0-3]):([0-5]\d)$/, value) do
      [_, h, m] -> {:ok, Time.new!(String.to_integer(h), String.to_integer(m), 0)}
      _ -> {:error, :invalid_quiet_hours}
    end
  end

  defp time(_value), do: {:error, :invalid_quiet_hours}

  defp tz(params, current, valid_zone?) do
    case fetch(params, "tz") do
      :missing ->
        {:ok, current.tz}

      {:ok, zone} when is_binary(zone) ->
        if valid_zone?.(zone), do: {:ok, zone}, else: {:error, :unknown_time_zone}

      _other ->
        {:error, :unknown_time_zone}
    end
  end

  defp phone(params, current) do
    case fetch(params, "phone") do
      :missing ->
        {:ok, current.phone}

      {:ok, nil} ->
        {:ok, nil}

      {:ok, phone} when is_binary(phone) ->
        phone = String.trim(phone)

        cond do
          phone == "" -> {:ok, nil}
          Regex.match?(@phone, phone) -> {:ok, phone}
          true -> {:error, :invalid_phone}
        end

      _other ->
        {:error, :invalid_phone}
    end
  end

  defp share(params, current, phone) do
    share =
      case fetch(params, "share_phone") do
        :missing -> current.share_phone and not is_nil(phone)
        {:ok, value} -> value
      end

    cond do
      share not in [true, false] -> {:error, :invalid_share_phone}
      share and is_nil(phone) -> {:error, :phone_required}
      true -> {:ok, share}
    end
  end

  @doc "Settings as the person reads them back."
  def present(settings) do
    settings = effective(settings)

    %{
      quiet_hours:
        if(settings.quiet_from,
          do: %{from: hhmm(settings.quiet_from), to: hhmm(settings.quiet_to)},
          else: nil
        ),
      tz: settings.tz,
      share_phone: settings.share_phone,
      phone: settings.phone
    }
  end

  def hhmm(%Time{} = time), do: time |> Time.to_iso8601() |> String.slice(0, 5)
  def hhmm(nil), do: nil

  defp fetch(params, key) do
    cond do
      Map.has_key?(params, key) -> {:ok, Map.get(params, key)}
      Map.has_key?(params, String.to_atom(key)) -> {:ok, Map.get(params, String.to_atom(key))}
      true -> :missing
    end
  end

  defp get(map, key), do: Map.get(map, key, Map.get(map, String.to_atom(key)))
end
