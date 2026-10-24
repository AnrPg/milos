defmodule Palee.Infrastructure.Guides.EctoGuideProgressStore do
  @moduledoc "Ecto adapter of walkthrough progress (ADR-193); row security admits only the owner's rows."

  @behaviour Palee.Guides.Ports.GuideProgressStore

  import Ecto.Query

  alias Palee.Guides.GuideProgress
  alias Palee.Repo

  @impl true
  def list(%{user_id: user_id}) do
    GuideProgress
    |> where([g], g.user_id == ^user_id)
    |> order_by([g], asc: g.guide_id)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def update(%{user_id: user_id}, guide_id, now, fun) do
    Repo.transaction(fn ->
      existing =
        GuideProgress
        |> where([g], g.user_id == ^user_id and g.guide_id == ^guide_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      count = if existing, do: 0, else: count(user_id)

      with {:ok, attrs} <- fun.(existing && normalize(existing), count),
           {:ok, row} <- write(existing, user_id, guide_id, attrs, now) do
        normalize(row)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def delete(%{user_id: user_id}, guide_id) do
    GuideProgress
    |> where([g], g.user_id == ^user_id and g.guide_id == ^guide_id)
    |> Repo.delete_all()

    :ok
  end

  defp count(user_id) do
    GuideProgress
    |> where([g], g.user_id == ^user_id)
    |> Repo.aggregate(:count)
  end

  defp write(nil, user_id, guide_id, attrs, now) do
    %GuideProgress{user_id: user_id, guide_id: guide_id}
    |> Ecto.Changeset.change(Map.merge(attrs, %{inserted_at: now, updated_at: now}))
    |> Repo.insert()
  end

  defp write(%GuideProgress{} = existing, _user_id, _guide_id, attrs, now) do
    existing
    |> Ecto.Changeset.change(Map.put(attrs, :updated_at, now))
    |> Repo.update()
  end

  defp normalize(%GuideProgress{} = g),
    do: %{
      guide_id: g.guide_id,
      version: g.version,
      status: g.status,
      step: g.step,
      runs: g.runs,
      started_at: g.started_at,
      completed_at: g.completed_at,
      updated_at: g.updated_at
    }
end
