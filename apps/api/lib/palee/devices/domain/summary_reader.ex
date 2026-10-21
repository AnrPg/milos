defmodule Palee.Devices.Domain.SummaryReader do
  @moduledoc """
  The provider-neutral side of ingestion (ADR-161, ADR-172): whatever sent
  a record (a Garmin push, the phone's Apple Health or Health Connect), it
  is read here into the same facts per kind, so one set of import rules
  (dedupe, matching, manual-wins, consent) serves every provider.

  - `activity` → started_at, duration, sport, numbers
  - `sleep` → bed_at, wake_at, local day
  - `weight` → taken_at, metrics
  - `daily` → a day's resting heart rate
  - `steps` → a day's steps (phones only)
  """

  alias Palee.Devices.Domain.{Catalog, GarminSummary, PhoneHealthSample}

  @doc "`{:ok, facts}` or `{:error, reason}` for one record of `kind` from `provider`."
  def read(provider, kind, record) do
    case {reader(provider), kind} do
      {nil, _kind} ->
        {:error, :unknown_provider}

      {GarminSummary, "steps"} ->
        {:error, :unsupported_kind}

      {module, kind} when kind in ~w(activity sleep weight daily steps) ->
        apply_kind(module, kind, record)

      _other ->
        {:error, :unsupported_kind}
    end
  end

  @doc "The dedupe id of a record (unique per person, provider and kind)."
  def provider_id("garmin", _kind, record), do: GarminSummary.provider_id(record)

  def provider_id(provider, kind, record) do
    if Catalog.phone_provider?(provider), do: PhoneHealthSample.provider_id(kind, record)
  end

  @doc "What of a record is kept in the import log."
  def trim("garmin", kind, record), do: GarminSummary.trim(kind, record)
  def trim(_provider, kind, record), do: PhoneHealthSample.trim(kind, record)

  defp reader("garmin"), do: GarminSummary

  defp reader(provider) do
    if Catalog.phone_provider?(provider), do: PhoneHealthSample
  end

  defp apply_kind(module, "activity", record), do: module.activity(record)
  defp apply_kind(module, "sleep", record), do: module.sleep(record)
  defp apply_kind(module, "weight", record), do: module.weight(record)
  defp apply_kind(module, "daily", record), do: module.daily(record)
  defp apply_kind(module, "steps", record), do: module.steps(record)
end
