defmodule Palee.Organizations.Domain.TimeZonePolicy do
  @moduledoc """
  The gym's time zone (ADR-176): the clock every gym-local rule reads (the
  day a class belongs to, morning alerts, check-in days, event times).

  `organization_settings.timezone_source` says how the zone was learnt:

    * `"confirmed"` - an admin (or the vendor) set it. Only another
      confirmation changes it.
    * `"inferred"` - guessed from a staff member's device (browser zone, or
      an IP-derived zone when the edge provides one) until someone confirms.
    * `nil` - never set; the platform default applies and onboarding asks.
  """

  @sources ~w(confirmed inferred)
  @utc_zones ["UTC", "Etc/UTC", "Etc/GMT", "GMT"]

  def sources, do: @sources

  @doc "Palee's default zone, used only while a gym's zone is unknown."
  def default_zone,
    do: Application.get_env(:palee, :default_organization_timezone, "Europe/Athens")

  @doc "An IANA zone the time zone database knows."
  def valid?(zone) when is_binary(zone) and zone != "",
    do: String.length(zone) <= 100 and match?({:ok, _now}, DateTime.now(zone))

  def valid?(_zone), do: false

  @doc "The zone gym-local rules read: the stored one once known, else the default."
  def resolve(%{timezone: zone, timezone_source: source}) when source in @sources,
    do: if(valid?(zone), do: zone, else: default_zone())

  def resolve(_settings), do: default_zone()

  @doc "Whether an admin confirmed the zone (the onboarding step)."
  def confirmed?(%{timezone_source: "confirmed"}), do: true
  def confirmed?(_settings), do: false

  @doc "A guess never replaces a confirmed zone; a confirmation always applies."
  def accept?(_current_source, "confirmed"), do: true
  def accept?(current_source, "inferred"), do: current_source != "confirmed"
  def accept?(_current_source, _source), do: false

  @doc """
  The best guess among candidate zones, most trusted first (the device's own
  zone, then an IP-derived one). A UTC zone says nothing about where the gym
  is and is skipped.
  """
  def infer(candidates) when is_list(candidates),
    do: Enum.find(candidates, &(valid?(&1) and &1 not in @utc_zones))
end
