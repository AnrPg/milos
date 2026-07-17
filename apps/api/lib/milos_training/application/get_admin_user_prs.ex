defmodule MilosTraining.Application.GetAdminUserPRs do
  @moduledoc false

  alias MilosTraining.Application.ListUserPRs
  alias MilosTraining.{Identity, Pantheon}

  def call(user_id) do
    with %{} <- Identity.find_by_id(user_id) || {:error, :not_found},
         {:ok, prs} <- ListUserPRs.call(user_id) do
      {:ok, %{user_id: user_id, prs: Enum.map(prs, &serialize(&1, user_id))}}
    end
  end

  defp serialize(pr, user_id) do
    history =
      case Pantheon.get_pr_history(pr.id, user_id) do
        {:ok, entries} -> Enum.map(entries, &serialize_history/1)
        _error -> []
      end

    %{
      id: pr.id,
      name: pr.name,
      current_score: pr.current_score,
      unit: pr.unit,
      higher_is_better: pr.higher_is_better,
      beaten_on: pr.beaten_on,
      supporting_metrics: pr.supporting_metrics || %{},
      notes: pr.notes,
      updated_at: pr.updated_at,
      history: history
    }
  end

  defp serialize_history(entry) do
    %{
      id: entry.id,
      score: entry.score,
      beaten_on: entry.beaten_on,
      supporting_metrics: entry.supporting_metrics || %{},
      notes: entry.notes,
      inserted_at: entry.inserted_at
    }
  end
end
