defmodule Palee.Application.IngestExecutionInteractions do
  @moduledoc """
  Ingests a batch of client-only execution interaction signals (ADR-123) -
  pause/resume, manual skips and restarts, round taps, on-the-fly adjusts,
  ready screen and get-ready countdown, finish-wizard steps, cast mode - as
  `execution_interaction` analytics events.

  * Scope: only the execution's owner may report interactions; the events are
    recorded in the execution's own tenant (the `/api/executions` routes are
    user-scoped), so the client never names an organization.
  * Allowlist: kinds and metadata are validated by the Analytics
    `ExecutionInteraction` allowlist; any invalid event rejects the batch.
  * Idempotent: each event dedupes on `user_id:client_event_id`, so an
    offline retry of the same batch is accepted and ignored.

  Returns `{:ok, %{accepted: n, duplicates: m}}`, `{:error, :not_found}` or
  `{:error, {:invalid_execution_interactions, errors}}`.
  """

  alias Palee.{Analytics, Execution}

  def call(user_context, execution_id, user_id, events) when is_binary(user_id) do
    with {:ok, execution} <- fetch_owned_execution(user_context, execution_id, user_id),
         {:ok, interactions} <-
           Analytics.validate_execution_interactions(events, DateTime.utc_now()),
         {:ok, rows} <- build_rows(execution, user_id, interactions),
         {:ok, result} <- record(execution.organization_id, rows) do
      {:ok, %{accepted: result.inserted, duplicates: result.duplicates}}
    end
  end

  def call(_user_context, _execution_id, _user_id, _events), do: {:error, :forbidden}

  defp fetch_owned_execution(user_context, execution_id, user_id) do
    with {:ok, execution_id} <- uuid(execution_id),
         %{user_id: ^user_id, organization_id: organization_id} = execution
         when is_binary(organization_id) <-
           Execution.with_execution_context(scope(user_context, user_id), fn ->
             Execution.get_execution(execution_id)
           end) do
      {:ok, execution}
    else
      _missing_or_foreign -> {:error, :not_found}
    end
  end

  defp build_rows(execution, user_id, interactions) do
    interactions
    |> Enum.reduce_while({:ok, []}, fn interaction, {:ok, rows} ->
      case Analytics.build_event("execution_interaction", nil, execution, %{
             organization_id: execution.organization_id,
             user_id: user_id,
             occurred_at: interaction.occurred_at,
             dedupe_key: "#{user_id}:#{interaction.client_event_id}",
             metadata:
               Map.merge(interaction.metadata, %{
                 "kind" => interaction.kind,
                 "client_event_id" => interaction.client_event_id
               })
           }) do
        {:ok, row} -> {:cont, {:ok, [row | rows]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp record(organization_id, rows) do
    Analytics.with_tenant_context(%{organization_id: organization_id}, fn ->
      Analytics.record_events(rows)
    end)
  end

  defp scope(%{user_id: user_id} = context, user_id), do: context
  defp scope(_context, user_id), do: %{user_id: user_id}

  defp uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end
end
