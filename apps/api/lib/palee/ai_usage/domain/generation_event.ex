defmodule Palee.AiUsage.Domain.GenerationEvent do
  @moduledoc """
  The `[:palee, :ai, :generation]` telemetry event (ADR-152): emitted by every
  model adapter once per billed call, so metering never depends on which
  feature or agent made the call.

  Measurements: the `TokenUsage` fields and `duration_ms`.

  Metadata:
    * `provider`, `model` (as requested), `model_version` (as reported);
    * `occurred_at` – when the call returned;
    * the caller's metering context (see `metering/1`): `operation_id`
      (groups the calls of one user action), `feature`, `agent`, and the
      tenant (`organization_id`, `user_id`) when the call was made for one.
  """

  alias Palee.AiUsage.Domain.TokenUsage

  @event [:palee, :ai, :generation]
  @metering_keys [:operation_id, :feature, :organization_id, :user_id]

  def name, do: @event

  @doc "The metering context of adapter `options` (their `:metering` map)."
  def metering(%{} = options), do: options |> Map.get(:metering) |> metering_context()
  def metering(_options), do: %{}

  @doc "The metering keys a caller may pass through to adapters; the rest is dropped."
  def metering_context(%{} = metering), do: Map.take(metering, @metering_keys)
  def metering_context(_metering), do: %{}

  def measurements(%TokenUsage{} = usage, duration_ms) do
    usage |> TokenUsage.to_map() |> Map.put(:duration_ms, duration_ms)
  end

  @doc "Record attributes for a persisted usage row, from one event."
  def to_record_attrs(measurements, metadata) do
    %{
      usage: TokenUsage.from_map(measurements),
      duration_ms: Map.get(measurements, :duration_ms),
      operation_id: Map.get(metadata, :operation_id),
      feature: Map.get(metadata, :feature),
      agent: Map.get(metadata, :agent),
      provider: Map.get(metadata, :provider),
      model: Map.get(metadata, :model),
      model_version: Map.get(metadata, :model_version),
      occurred_at: Map.get(metadata, :occurred_at),
      user_id: Map.get(metadata, :user_id)
    }
  end
end
