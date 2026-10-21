defmodule Palee.Infrastructure.Insights.EctoInsightStore do
  @moduledoc """
  Ecto adapter of the Insights store (ADR-166). Row security admits only
  the owner's rows; the candidate lookup is a definer function answering
  ids only.
  """

  @behaviour Palee.Insights.Ports.InsightStore

  import Ecto.Query

  alias Palee.Insights.Insight
  alias Palee.Repo

  @impl true
  def list(user_id) do
    Insight
    |> where([i], i.user_id == ^user_id)
    |> Repo.all()
  end

  @impl true
  def put_results(user_id, results, from, to, now) do
    rows =
      Enum.map(results, fn result ->
        %{
          id: Ecto.UUID.generate(),
          user_id: user_id,
          rule: result.rule,
          status: result.status,
          value: result.value,
          fingerprint: result.fingerprint,
          period_start: from,
          period_end: to,
          computed_at: now,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(Insight, rows,
      on_conflict:
        {:replace,
         [:status, :value, :fingerprint, :period_start, :period_end, :computed_at, :updated_at]},
      conflict_target: [:user_id, :rule]
    )

    :ok
  end

  @impl true
  def dismiss(user_id, rule, now) do
    {count, _} =
      Insight
      |> where(
        [i],
        i.user_id == ^user_id and i.rule == ^rule and i.status == "finding" and
          not is_nil(i.fingerprint)
      )
      |> update([i], set: [dismissed_fingerprint: i.fingerprint, dismissed_at: ^now])
      |> Repo.update_all([])

    if count == 1, do: :ok, else: {:error, :not_found}
  end

  @impl true
  def restore(user_id) do
    Insight
    |> where([i], i.user_id == ^user_id and not is_nil(i.dismissed_fingerprint))
    |> Repo.update_all(set: [dismissed_fingerprint: nil, dismissed_at: nil])

    :ok
  end

  @impl true
  def delete_all(user_id) do
    Insight
    |> where([i], i.user_id == ^user_id)
    |> Repo.delete_all()

    :ok
  end

  @impl true
  def candidates(since, after_id, limit) do
    after_id = after_id && Ecto.UUID.dump!(after_id)

    %{rows: rows} =
      Repo.query!("SELECT id FROM palee_insight_candidates($1, $2, $3) AS id", [
        DateTime.to_naive(since),
        after_id,
        limit
      ])

    Enum.map(rows, fn [id] -> Ecto.UUID.load!(id) end)
  end
end
