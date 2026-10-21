defmodule Palee.Pantheon.Domain.PRView do
  @moduledoc """
  Read-only PR projection shared by every non-owner reader (coach dossier,
  sharing grantees): the PR fields plus its score history, without owner-only
  management data.
  """

  def with_history(pr, history) when is_map(pr) and is_list(history) do
    %{
      id: pr.id,
      organization_id: Map.get(pr, :organization_id),
      name: pr.name,
      current_score: pr.current_score,
      unit: pr.unit,
      higher_is_better: pr.higher_is_better,
      beaten_on: pr.beaten_on,
      supporting_metrics: pr.supporting_metrics || %{},
      updated_at: pr.updated_at,
      history: Enum.map(history, &history_entry/1)
    }
  end

  defp history_entry(entry) do
    %{
      id: entry.id,
      score: entry.score,
      beaten_on: entry.beaten_on,
      supporting_metrics: entry.supporting_metrics || %{},
      inserted_at: entry.inserted_at
    }
  end
end
