defmodule Palee.Infrastructure.PersonalData.EctoExportStore do
  @moduledoc "Ecto adapter of `Palee.PersonalData.Ports.ExportStore` (ADR-267)."

  @behaviour Palee.PersonalData.Ports.ExportStore

  import Ecto.Query

  alias Palee.PersonalData.Export
  alias Palee.Repo

  @impl true
  def list(user_id) do
    Export
    |> where([e], e.user_id == ^user_id)
    |> order_by([e], desc: e.requested_at, desc: e.id)
    |> Repo.all()
  end

  @impl true
  def get(id, user_id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Export |> where([e], e.id == ^id and e.user_id == ^user_id) |> Repo.one()
      :error -> nil
    end
  end

  @impl true
  def insert(attrs), do: attrs |> Export.create_changeset() |> Repo.insert()

  @impl true
  def finish(%Export{id: id, user_id: user_id}, attrs) do
    Repo.transaction(fn ->
      case Export
           |> where([e], e.id == ^id and e.user_id == ^user_id)
           |> lock("FOR UPDATE")
           |> Repo.one() do
        %Export{status: "pending"} = export ->
          case export |> Export.finish_changeset(attrs) |> Repo.update() do
            {:ok, finished} -> finished
            {:error, changeset} -> Repo.rollback(changeset)
          end

        _other ->
          Repo.rollback(:not_pending)
      end
    end)
  end
end
