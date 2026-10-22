defmodule Palee.TimeZones.ZonedTime do
  @moduledoc """
  One canonical clock, converted on demand (ADR-179).

  Every moment is stored once, in UTC. What a moment *means* to people
  depends on whose clock reads it:

    * the **organiser's zone** - the gym, or an event's own zone when it
      happens elsewhere - is the clock a class or an event is planned in
      and the one people see first;
    * the **viewer's zone** - the zone the reader's device last reported -
      only matters when it reads that moment differently (another offset at
      that instant), and then adds "your time" beside the organiser's.

  Pure functions over IANA zone names; nothing here reads a database.
  """

  @utc_zones ["UTC", "Etc/UTC", "Etc/GMT", "GMT", "Etc/Universal", "Zulu"]

  @type style :: :date_time | :time
  @type localizer :: (String.t(), map() -> String.t())

  @doc "Palee's default zone: the clock used while a gym's or a person's zone is unknown."
  def default_zone,
    do: Application.get_env(:palee, :default_organization_timezone, "Europe/Athens")

  @doc "The zone if known and valid, else the default."
  def or_default(zone), do: if(valid?(zone), do: zone, else: default_zone())

  @doc "An IANA zone the time zone database knows."
  def valid?(zone) when is_binary(zone) and zone != "",
    do: String.length(zone) <= 100 and match?({:ok, _now}, DateTime.now(zone))

  def valid?(_zone), do: false

  @doc "A UTC alias, which says nothing about where someone is."
  def utc?(zone), do: zone in @utc_zones

  @doc "A moment from a `DateTime` or an ISO 8601 string (payloads), else nil."
  def parse(%DateTime{} = at), do: at

  def parse(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> at
      _invalid -> nil
    end
  end

  def parse(_value), do: nil

  @doc "The moment on the zone's wall clock; UTC when the zone is unknown."
  def local(%DateTime{} = at, zone) do
    case valid?(zone) && DateTime.shift_zone(at, zone) do
      {:ok, local} -> local
      _unknown -> DateTime.shift_zone!(at, "Etc/UTC")
    end
  end

  @doc "The calendar day the moment falls on in the zone."
  def local_date(%DateTime{} = at, zone), do: at |> local(zone) |> DateTime.to_date()

  @doc "The zone's UTC offset at that moment, in seconds (DST included)."
  def offset_seconds(%DateTime{} = at, zone) do
    local = local(at, zone)
    local.utc_offset + local.std_offset
  end

  @doc """
  Both zones read the moment alike: same offset at that instant. Zones that
  differ only in name (Europe/Athens, Europe/Bucharest) or only in another
  season count as alike for that moment.
  """
  def same_clock?(%DateTime{} = at, zone_a, zone_b) do
    cond do
      zone_a == zone_b -> true
      not valid?(zone_a) or not valid?(zone_b) -> false
      true -> offset_seconds(at, zone_a) == offset_seconds(at, zone_b)
    end
  end

  @doc """
  A short, locale-neutral name for a zone: its city
  ("America/Argentina/Buenos_Aires" -> "Buenos Aires"), "UTC" for UTC.
  """
  def label(zone) when is_binary(zone) do
    cond do
      utc?(zone) ->
        "UTC"

      String.contains?(zone, "/") ->
        zone |> String.split("/") |> List.last() |> String.replace("_", " ")

      true ->
        zone
    end
  end

  def label(_zone), do: "UTC"

  @doc "«24/10 19:00» (`:date_time`) or «19:00» (`:time`) on the zone's clock."
  @spec format(DateTime.t(), String.t() | nil, style()) :: String.t()
  def format(%DateTime{} = at, zone, style \\ :date_time) do
    local = local(at, zone)
    text = Calendar.strftime(local, pattern(style))
    if valid?(zone), do: text, else: text <> " UTC"
  end

  @doc """
  The moment as a reader sees it: on the organiser's clock, and when the
  reader's zone reads it differently, also on theirs:

      «24/10 19:00»                                  same clock or reader unknown
      «24/10 19:00 Athens · 18:00 your time»         reader in London
      «24/10 19:00 Athens · 25/10 02:00 your time»   reader's day differs

  The reader's part repeats the date only when their day differs.
  """
  @spec format_for(DateTime.t(), String.t() | nil, String.t() | nil, localizer(), style()) ::
          String.t()
  def format_for(%DateTime{} = at, organiser_zone, viewer_zone, localize, style \\ :date_time) do
    organiser_text = format(at, organiser_zone, style)

    if valid?(organiser_zone) and valid?(viewer_zone) and
         not same_clock?(at, organiser_zone, viewer_zone) do
      viewer_style =
        if style == :time or
             local_date(at, organiser_zone) == local_date(at, viewer_zone),
           do: :time,
           else: :date_time

      localize.("%{time} %{zone} · %{local} your time", %{
        time: organiser_text,
        zone: label(organiser_zone),
        local: format(at, viewer_zone, viewer_style)
      })
    else
      organiser_text
    end
  end

  @doc """
  The UTC moment a wall-clock time in a zone stands for. A time skipped by a
  DST jump moves to just after the jump; a repeated one takes the first.
  """
  def to_utc(%Date{} = date, %Time{} = time, zone) do
    zone = if valid?(zone), do: zone, else: "Etc/UTC"

    case DateTime.new(date, time, zone) do
      {:ok, at} -> DateTime.shift_zone!(at, "Etc/UTC")
      {:ambiguous, first, _second} -> DateTime.shift_zone!(first, "Etc/UTC")
      {:gap, _before, after_gap} -> DateTime.shift_zone!(after_gap, "Etc/UTC")
      {:error, _reason} -> DateTime.new!(date, time, "Etc/UTC")
    end
  end

  @doc "The UTC moment the zone's day begins (00:00, or the first moment after a DST gap)."
  def start_of_day(%Date{} = date, zone), do: to_utc(date, ~T[00:00:00], zone)

  defp pattern(:date_time), do: "%d/%m %H:%M"
  defp pattern(:time), do: "%H:%M"
end
