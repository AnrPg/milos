defmodule MilosTraining.Application.RecordAiUsage do
  @moduledoc """
  Records every billed model call (ADR-141) for the gym it was made for.

  Model adapters emit `[:milos, :ai, :generation]` once per call; `attach/0`
  (called once at application start) subscribes `handle_event/4`, which runs
  synchronously in the calling process. Calls without a tenant (e.g. local
  measurement runs) are not persisted. Metering is a side effect: the handler
  never raises, so a recording failure never fails the user's action and
  telemetry never detaches the handler.
  """

  require Logger

  alias MilosTraining.AiUsage

  @handler_id "milos-ai-usage-recorder"

  def attach do
    :telemetry.detach(@handler_id)
    :telemetry.attach(@handler_id, AiUsage.generation_event(), &__MODULE__.handle_event/4, nil)
  end

  def handle_event(_event, measurements, metadata, _config), do: call(measurements, metadata)

  def call(measurements, %{organization_id: organization_id} = metadata)
      when is_binary(organization_id) do
    context = %{organization_id: organization_id, user_id: Map.get(metadata, :user_id)}

    case AiUsage.record_usage(context, AiUsage.record_attrs(measurements, metadata)) do
      {:ok, _record} -> :ok
      {:error, reason} -> report_failure(metadata, reason)
    end
  rescue
    exception -> report_failure(metadata, exception.__struct__)
  end

  def call(_measurements, _metadata), do: :ok

  defp report_failure(metadata, reason) do
    Logger.warning(
      "ai_usage_record_failed feature=#{Map.get(metadata, :feature)} operation_id=#{Map.get(metadata, :operation_id)} reason=#{inspect(reason)}"
    )

    :telemetry.execute([:milos, :ai_usage, :record_failed], %{count: 1}, %{
      feature: Map.get(metadata, :feature),
      reason: inspect(reason)
    })

    :ok
  end
end
