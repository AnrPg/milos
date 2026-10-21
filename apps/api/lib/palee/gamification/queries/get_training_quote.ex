defmodule Palee.Gamification.Queries.GetTrainingQuote do
  import Ecto.Query

  alias Palee.Gamification.TrainingQuote
  alias Palee.Repo

  def for_subject(%Date{} = date, subject_id) when is_binary(subject_id) do
    count = Repo.aggregate(TrainingQuote, :count)

    if count == 0 do
      nil
    else
      offset = :erlang.phash2({Date.to_iso8601(date), subject_id}, count)

      TrainingQuote
      |> order_by([quote], asc: quote.id)
      |> offset(^offset)
      |> limit(1)
      |> Repo.one()
    end
  end
end
