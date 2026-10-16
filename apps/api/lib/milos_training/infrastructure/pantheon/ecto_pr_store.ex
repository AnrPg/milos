defmodule MilosTraining.Infrastructure.Pantheon.EctoPRStore do
  @behaviour MilosTraining.Pantheon.Ports.PRStore

  import Ecto.Query

  alias MilosTraining.Pantheon.{PRHistory, PRRecord, PRShareGrant}
  alias MilosTraining.Pantheon.Domain.PRHistoryPolicy
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
  def list_organization_prs(user_id, organization_id) do
    PRRecord
    |> where([r], r.user_id == ^user_id and r.organization_id == ^organization_id)
    |> order_by([r], desc: r.beaten_on, desc: r.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_pr/1)
  end

  @impl true
  def search_user_prs(user_id, query) do
    search_term = ilike_pattern(query)

    PRRecord
    |> where([r], r.user_id == ^user_id)
    |> where([r], fragment("? ILIKE ? ESCAPE '\\'", r.name, ^search_term))
    |> order_by([r], desc: r.beaten_on)
    |> Repo.all()
    |> Enum.map(&normalize_pr/1)
  end

  defp ilike_pattern(value) do
    escaped =
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    "%#{escaped}%"
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
    params
    |> PRRecord.create_changeset()
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
          changeset = PRRecord.changeset(existing, params)

          case Repo.update(changeset) do
            {:ok, updated} ->
              if PRHistoryPolicy.snapshot_required?(changeset.changes) do
                %PRHistory{}
                |> PRHistory.changeset(%{
                  organization_id: existing.organization_id,
                  pr_record_id: id,
                  score: existing.current_score,
                  beaten_on: existing.beaten_on,
                  supporting_metrics: existing.supporting_metrics,
                  notes: existing.notes
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
  def edit_pr(id, params) do
    case Repo.get(PRRecord, id) do
      nil ->
        {:error, :not_found}

      existing ->
        existing
        |> PRRecord.changeset(params)
        |> Repo.update()
        |> normalize_result(&normalize_pr/1)
    end
  end

  @impl true
  def delete_pr(id, user_id) do
    case Repo.get_by(PRRecord, id: id, user_id: user_id) do
      nil ->
        {:error, :not_found}

      pr ->
        Repo.delete!(pr)
        :ok
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

  # Every history entry of the user's PRs with its record's name and unit, for
  # the progress timeline (ADR-098).
  @impl true
  def list_user_pr_history(user_id) do
    PRHistory
    |> join(:inner, [h], r in PRRecord, on: r.id == h.pr_record_id)
    |> where([_h, r], r.user_id == ^user_id)
    |> order_by([h], asc: h.beaten_on, asc: h.inserted_at)
    |> select([h, r], {h, r.name, r.unit, r.higher_is_better})
    |> Repo.all()
    |> Enum.map(fn {history, name, unit, higher_is_better} ->
      history
      |> normalize_history()
      |> Map.merge(%{name: name, unit: unit, higher_is_better: higher_is_better})
    end)
  end

  @impl true
  def count_user_prs(user_id) do
    PRRecord
    |> where([r], r.user_id == ^user_id)
    |> Repo.aggregate(:count, :id)
  end

  @impl true
  def set_record_visibility(id, user_id, rung) do
    case Repo.get_by(PRRecord, id: id, user_id: user_id) do
      nil ->
        {:error, :not_found}

      record ->
        record
        |> PRRecord.visibility_changeset(rung)
        |> Repo.update()
        |> normalize_result(&normalize_pr/1)
    end
  end

  # Only gym PRs move: a personal PR has no coach and stays private.
  @impl true
  def move_records(user_id, from, to) do
    {count, _rows} =
      PRRecord
      |> where([r], r.user_id == ^user_id and not is_nil(r.organization_id))
      |> where([r], r.journal_visibility in ^from)
      |> Repo.update_all(set: [journal_visibility: to, updated_at: DateTime.utc_now()])

    count
  end

  @impl true
  def list_owned_grants(user_id) do
    PRShareGrant
    |> where([g], g.user_id == ^user_id and is_nil(g.revoked_at))
    |> order_by([g], asc: g.created_at)
    |> Repo.all()
    |> Enum.map(&normalize_grant/1)
  end

  @impl true
  def list_received_grants(grantee_user_id) do
    PRShareGrant
    |> where([g], g.grantee_user_id == ^grantee_user_id and is_nil(g.revoked_at))
    |> order_by([g], asc: g.created_at)
    |> Repo.all()
    |> Enum.map(&normalize_grant/1)
  end

  @impl true
  def get_active_grant(user_id, grantee_user_id) do
    PRShareGrant
    |> where([g], g.user_id == ^user_id and g.grantee_user_id == ^grantee_user_id)
    |> where([g], is_nil(g.revoked_at))
    |> Repo.one()
    |> case do
      nil -> nil
      grant -> normalize_grant(grant)
    end
  end

  @impl true
  def create_grant(user_id, grantee_user_id) do
    %{user_id: user_id, grantee_user_id: grantee_user_id}
    |> PRShareGrant.create_changeset()
    |> Repo.insert()
    |> normalize_result(&normalize_grant/1)
  end

  @impl true
  def revoke_grant(user_id, grant_id, revoked_at) do
    PRShareGrant
    |> where([g], g.id == ^grant_id and g.user_id == ^user_id and is_nil(g.revoked_at))
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      grant ->
        grant
        |> PRShareGrant.revoke_changeset(revoked_at)
        |> Repo.update()
        |> normalize_result(&normalize_grant/1)
    end
  end

  defp normalize_grant(grant) do
    %{
      id: grant.id,
      user_id: grant.user_id,
      grantee_user_id: grant.grantee_user_id,
      created_at: DateTime.to_iso8601(grant.created_at),
      revoked_at: grant.revoked_at && DateTime.to_iso8601(grant.revoked_at)
    }
  end

  defp normalize_pr(pr) do
    %{
      id: pr.id,
      user_id: pr.user_id,
      organization_id: pr.organization_id,
      name: pr.name,
      current_score: Decimal.to_float(pr.current_score),
      unit: pr.unit,
      higher_is_better: pr.higher_is_better,
      beaten_on: Date.to_iso8601(pr.beaten_on),
      supporting_metrics: pr.supporting_metrics || %{},
      notes: pr.notes,
      journal_visibility: pr.journal_visibility,
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
      supporting_metrics: h.supporting_metrics || %{},
      notes: h.notes,
      inserted_at: DateTime.to_iso8601(h.inserted_at)
    }
  end

  defp normalize_result({:ok, record}, normalizer), do: {:ok, normalizer.(record)}
  defp normalize_result({:error, reason}, _normalizer), do: {:error, reason}
end
