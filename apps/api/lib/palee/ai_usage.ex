defmodule Palee.AiUsage do
  @moduledoc """
  AI usage metering (ADR-152): what each model call cost, per gym, feature
  and user action.

  Model adapters call `report_generation/3` once per billed call; the
  application records it for the call's tenant (`RecordAiUsage`). Anyone else
  (e.g. `mix palee.ai.measure_free_text`) can observe the same event.
  """

  alias Palee.AiUsage.Commands.RecordUsage
  alias Palee.AiUsage.Domain.{AiSettingsPolicy, GenerationEvent, PriceList, TokenUsage}
  alias Palee.AiUsage.Queries.{OperationUsage, UsageSummary}

  @doc """
  Emits the generation event for one billed call. `metadata` carries
  `provider`, `model`, `model_version`, `agent` and `occurred_at` plus the
  caller's metering context (`GenerationEvent.metering/1`).
  """
  def report_generation(%TokenUsage{} = usage, duration_ms, %{} = metadata) do
    :telemetry.execute(
      GenerationEvent.name(),
      GenerationEvent.measurements(usage, duration_ms),
      metadata
    )
  end

  defdelegate generation_event(), to: GenerationEvent, as: :name
  defdelegate metering(options), to: GenerationEvent
  defdelegate metering_context(metering), to: GenerationEvent
  defdelegate record_attrs(measurements, metadata), to: GenerationEvent, as: :to_record_attrs
  defdelegate token_usage_from_gemini(usage_metadata), to: TokenUsage, as: :from_gemini
  defdelegate token_usage_from_anthropic(usage), to: TokenUsage, as: :from_anthropic
  defdelegate cost(usage, model, date), to: PriceList
  defdelegate record_usage(context, attrs), to: RecordUsage, as: :call
  defdelegate operation_usage(context, operation_id), to: OperationUsage, as: :call
  defdelegate usage_summary(context, params \\ %{}), to: UsageSummary, as: :call

  # ADR-174: the gym's AI settings (its own key, encrypted; never returned).
  defdelegate get_settings(context), to: Palee.AiUsage.AiUsageStore
  defdelegate put_settings(context, changes), to: Palee.AiUsage.AiUsageStore

  defdelegate settings_update_changes(current, params, actor_id),
    to: AiSettingsPolicy,
    as: :update_changes

  defdelegate scaling_ready?(settings), to: AiSettingsPolicy
  defdelegate voice_ready?(settings), to: AiSettingsPolicy
  defdelegate settings_model(settings, default), to: AiSettingsPolicy, as: :model
  defdelegate public_settings(settings, default_model), to: AiSettingsPolicy, as: :public

  # ADR-117 reviewed tenant export/purge.
  def tenant_data_policy, do: Palee.AiUsage.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
