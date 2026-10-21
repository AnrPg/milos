defmodule MilosTraining.Application.GetMyInsights do
  @moduledoc """
  `GET /api/me/insights` and the dismiss/restore actions (ADR-166): the
  single Πρόοδος insights slot. Reads the stored results; computes them
  first when there are none yet, they are older than a day (a new member,
  or one the nightly job did not reach), or a journal section was switched
  off or on since (so a section switched off disappears at once and its
  values are cleared).
  """

  alias MilosTraining.Application.ComputeInsights
  alias MilosTraining.Insights

  def call(%{user_id: user_id} = context, now \\ DateTime.utc_now()) do
    settings = ComputeInsights.settings(context, user_id)
    rows = list(context)

    rows =
      if Insights.current?(rows, settings, now),
        do: rows,
        else: ComputeInsights.call(context, now, settings)

    {:ok, present(rows, settings)}
  end

  @doc "Hides one rule's current finding until it changes; answers the new slot."
  def dismiss(%{user_id: user_id} = context, rule, now \\ DateTime.utc_now()) do
    with true <- rule in Insights.rule_ids(),
         :ok <- Insights.with_context(context, fn -> Insights.dismiss(user_id, rule, now) end) do
      {:ok, current(context)}
    else
      _missing -> {:error, :not_found}
    end
  end

  @doc "Shows every dismissed finding again; answers the new slot."
  def restore(%{user_id: user_id} = context) do
    :ok = Insights.with_context(context, fn -> Insights.restore(user_id) end)
    {:ok, current(context)}
  end

  defp list(%{user_id: user_id} = context),
    do: Insights.with_context(context, fn -> Insights.list(user_id) end)

  defp current(%{user_id: user_id} = context),
    do: present(list(context), ComputeInsights.settings(context, user_id))

  defp present(rows, settings) do
    view = Insights.view(rows, settings)

    %{
      state: view.state,
      insights: Enum.map(view.insights, &insight/1),
      hidden_count: view.hidden_count,
      data_weeks: view.data_weeks,
      min_weeks: Insights.min_weeks(),
      window_weeks: Insights.window_weeks(),
      max_shown: Insights.max_shown(),
      computed_at: view.computed_at
    }
  end

  defp insight(row) do
    value = row.value || %{}

    %{
      rule: row.rule,
      variant: value["variant"],
      params: value["params"] || %{},
      weeks: value["weeks"] || 0,
      period_start: row.period_start,
      period_end: row.period_end
    }
  end
end
