defmodule MilosTraining.Application.GetAdminUserPRs do
  @moduledoc false

  alias MilosTraining.Application.ListUserPRs
  alias MilosTraining.Identity

  def call(user_id) do
    with %{} <- Identity.find_by_id(user_id) || {:error, :not_found},
         {:ok, prs} <- ListUserPRs.call(user_id) do
      {:ok, %{user_id: user_id, prs: Enum.map(prs, &serialize/1)}}
    end
  end

  defp serialize(pr) do
    %{
      id: pr.id,
      name: pr.name,
      current_score: pr.current_score,
      unit: pr.unit,
      higher_is_better: pr.higher_is_better,
      beaten_on: pr.beaten_on,
      supporting_metrics: pr.supporting_metrics || %{},
      notes: pr.notes,
      updated_at: pr.updated_at
    }
  end
end
