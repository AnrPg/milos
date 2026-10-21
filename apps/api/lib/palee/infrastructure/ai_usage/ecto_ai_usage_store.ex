defmodule Palee.Infrastructure.AiUsage.EctoAiUsageStore do
  @moduledoc "Ecto adapter of the AI usage store (ADR-152)."

  @behaviour Palee.AiUsage.Ports.AiUsageStore

  import Ecto.Query

  alias Palee.AiUsage.{GymAiSettings, UsageRecord}
  alias Palee.Repo

  @impl true
  def insert_record(%{organization_id: organization_id}, attrs) do
    organization_id
    |> UsageRecord.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, record} -> {:ok, normalize(record)}
      error -> error
    end
  end

  @impl true
  def list_operation(%{organization_id: organization_id}, operation_id) do
    UsageRecord
    |> where([r], r.organization_id == ^organization_id and r.operation_id == ^operation_id)
    |> order_by([r], asc: r.occurred_at, asc: r.id)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def summarize(%{organization_id: organization_id}, params) do
    UsageRecord
    |> where([r], r.organization_id == ^organization_id)
    |> filter(params)
    |> group_by([r], [r.feature, r.model])
    |> order_by([r], asc: r.feature, asc: r.model)
    |> select([r], %{
      feature: r.feature,
      model: r.model,
      operations: count(r.operation_id, :distinct),
      calls: count(r.id),
      input_tokens: coalesce(sum(r.input_tokens), 0),
      cached_input_tokens: coalesce(sum(r.cached_input_tokens), 0),
      output_tokens: coalesce(sum(r.output_tokens), 0),
      thinking_tokens: coalesce(sum(r.thinking_tokens), 0),
      cost_nano_usd: coalesce(sum(r.cost_nano_usd), 0),
      unpriced_calls: filter(count(r.id), is_nil(r.cost_nano_usd))
    })
    |> Repo.all()
    |> Enum.map(&integer_sums/1)
  end

  @impl true
  def get_settings(%{organization_id: organization_id}) do
    GymAiSettings
    |> where([s], s.organization_id == ^organization_id)
    |> Repo.one()
  end

  # One row per gym: created on the first write.
  @impl true
  def put_settings(%{organization_id: organization_id} = context, changes) do
    (get_settings(context) || %GymAiSettings{organization_id: organization_id})
    |> GymAiSettings.changeset(changes)
    |> Repo.insert_or_update()
  end

  defp filter(query, params) do
    Enum.reduce(params, query, fn
      {:from, %DateTime{} = from}, query ->
        where(query, [r], r.occurred_at >= ^from)

      {:to, %DateTime{} = to}, query ->
        where(query, [r], r.occurred_at < ^to)

      {:feature, feature}, query when is_binary(feature) ->
        where(query, [r], r.feature == ^feature)

      # ADR-175: one member's calls by one agent (the voice-log daily cap).
      {:user_id, user_id}, query when is_binary(user_id) ->
        where(query, [r], r.user_id == ^user_id)

      {:agent, agent}, query when is_binary(agent) ->
        where(query, [r], r.agent == ^agent)

      _other, query ->
        query
    end)
  end

  # SUM(integer) is numeric/bigint in Postgres; Postgrex returns Decimal for
  # numeric, so sums come back as integers here.
  defp integer_sums(row) do
    Map.new(row, fn
      {key, %Decimal{} = value} -> {key, Decimal.to_integer(value)}
      pair -> pair
    end)
  end

  defp normalize(%UsageRecord{} = record) do
    Map.take(record, [
      :id,
      :organization_id,
      :user_id,
      :operation_id,
      :feature,
      :agent,
      :provider,
      :model,
      :model_version,
      :input_tokens,
      :cached_input_tokens,
      :output_tokens,
      :thinking_tokens,
      :cost_nano_usd,
      :duration_ms,
      :occurred_at
    ])
  end
end
