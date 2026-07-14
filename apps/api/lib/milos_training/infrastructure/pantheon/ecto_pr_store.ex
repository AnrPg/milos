defmodule MilosTraining.Infrastructure.Pantheon.EctoPRStore do
  @behaviour MilosTraining.Pantheon.Ports.PRStore

  import Ecto.Query

  alias MilosTraining.Pantheon.{PRHistory, PRRecord}
  alias MilosTraining.Repo

  @impl true
  def list_user_prs(user_id) do
    PRRecord
    |> where([r], r.user_id == ^user_id)
    |> order_by([r], desc: r.beaten_on, desc: r.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_pr/1)
  end

  @impl true
  def search_user_prs(user_id, query) do
    search_term = "%#{String.replace(query, "%", "\\%")}%"

    PRRecord
    |> where([r], r.user_id == ^user_id)
    |> where([r], ilike(r.name, ^search_term))
    |> order_by([r], desc: r.beaten_on)
    |> Repo.all()
    |> Enum.map(&normalize_pr/1)
  end

  @impl true
  def get_pr(id) do
    case Repo.get(PRRecord, id) do
      nil -> nil
      pr -> normalize_pr(pr)
    end
  end

  @impl true
  def get_pr_for_user(id, user_id) do
    case Repo.get_by(PRRecord, id: id, user_id: user_id) do
      nil -> nil
      pr -> normalize_pr(pr)
    end
  end

  @impl true
  def create_pr(params) do
    %PRRecord{}
    |> PRRecord.changeset(params)
    |> Repo.insert()
    |> normalize_result(&normalize_pr/1)
  end

  @impl true
  def update_pr(id, params) do
    case Repo.get(PRRecord, id) do
      nil ->
        {:error, :not_found}

      existing ->
        Repo.transaction(fn ->
          old_score = existing.current_score

          case PRRecord.changeset(existing, params) |> Repo.update() do
            {:ok, updated} ->
              new_score = updated.current_score

              if Decimal.compare(new_score, old_score) != :eq do
                %PRHistory{}
                |> PRHistory.changeset(%{
                  pr_record_id: id,
                  score: old_score,
                  beaten_on: existing.beaten_on
                })
                |> Repo.insert!()
              end

              normalize_pr(updated)

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)
    end
  end

  @impl true
  def delete_pr(id, user_id) do
    case Repo.get_by(PRRecord, id: id, user_id: user_id) do
      nil -> {:error, :not_found}
      pr -> Repo.delete!(pr); :ok
    end
  end

  @impl true
  def list_pr_history(pr_record_id) do
    PRHistory
    |> where([h], h.pr_record_id == ^pr_record_id)
    |> order_by([h], desc: h.beaten_on, desc: h.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_history/1)
  end

  @impl true
  def count_user_prs(user_id) do
    PRRecord
    |> where([r], r.user_id == ^user_id)
    |> Repo.aggregate(:count, :id)
  end

  defp normalize_pr(pr) do
    %{
      id: pr.id,
      user_id: pr.user_id,
      name: pr.name,
      current_score: Decimal.to_float(pr.current_score),
      unit: pr.unit,
      higher_is_better: pr.higher_is_better,
      beaten_on: Date.to_iso8601(pr.beaten_on),
      inserted_at: DateTime.to_iso8601(pr.inserted_at),
      updated_at: DateTime.to_iso8601(pr.updated_at)
    }
  end

  defp normalize_history(h) do
    %{
      id: h.id,
      pr_record_id: h.pr_record_id,
      score: Decimal.to_float(h.score),
      beaten_on: Date.to_iso8601(h.beaten_on),
      inserted_at: DateTime.to_iso8601(h.inserted_at)
    }
  end

  defp normalize_result({:ok, record}, normalizer), do: {:ok, normalizer.(record)}
  defp normalize_result({:error, reason}, _normalizer), do: {:error, reason}
end
