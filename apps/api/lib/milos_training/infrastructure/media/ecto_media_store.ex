defmodule MilosTraining.Infrastructure.Media.EctoMediaStore do
  @moduledoc "Ecto adapter of the Media store (ADR-148)."

  @behaviour MilosTraining.Media.Ports.MediaStore

  import Ecto.Query

  alias MilosTraining.Media.{AccountObject, TenantObject}
  alias MilosTraining.Repo

  @impl true
  def create(%{organization_id: organization_id} = context, :tenant, attrs) do
    attrs
    |> Map.merge(%{organization_id: organization_id, uploaded_by_id: Map.get(context, :user_id)})
    |> TenantObject.create_changeset()
    |> Repo.insert()
    |> normalize_result()
  end

  def create(%{user_id: user_id}, :account, attrs) do
    attrs
    |> Map.put(:user_id, user_id)
    |> AccountObject.create_changeset()
    |> Repo.insert()
    |> normalize_result()
  end

  @impl true
  def get(context, scope, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> context |> owned(scope) |> where([m], m.id == ^id) |> Repo.one() |> normalize()
      :error -> nil
    end
  end

  @impl true
  def list(context, scope, ids) do
    ids = for id <- ids, {:ok, id} <- [Ecto.UUID.cast(id)], do: id

    context
    |> owned(scope)
    |> where([m], m.id in ^ids)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def mark_ready(context, scope, id, attrs) do
    {count, rows} =
      context
      |> owned(scope)
      |> where([m], m.id == ^id and m.status == "pending")
      |> select([m], m)
      |> Repo.update_all(
        set: [
          status: "ready",
          byte_size: attrs.byte_size,
          width: attrs.width,
          height: attrs.height,
          updated_at: DateTime.utc_now()
        ]
      )

    case {count, rows} do
      {1, [row]} -> {:ok, normalize(row)}
      _none -> {:error, :media_not_found}
    end
  end

  @impl true
  def set_attached(_context, _scope, [], _at), do: :ok

  def set_attached(context, scope, ids, at) do
    context
    |> owned(scope)
    |> where([m], m.id in ^ids)
    |> Repo.update_all(set: [attached_at: at, updated_at: DateTime.utc_now()])

    :ok
  end

  @impl true
  def delete(_context, _scope, []), do: {:ok, []}

  def delete(context, scope, ids) do
    {_count, rows} =
      context
      |> owned(scope)
      |> where([m], m.id in ^ids)
      |> select([m], m)
      |> Repo.delete_all()

    {:ok, Enum.map(rows, &normalize/1)}
  end

  @impl true
  def list_unattached(context, scope, before) do
    context
    |> owned(scope)
    |> where([m], is_nil(m.attached_at) and m.inserted_at < ^before)
    |> limit(500)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def account_orphan_owner_ids(before) do
    %{rows: rows} =
      Repo.query!("SELECT id FROM milos_account_media_orphan_owner_ids($1) AS id", [before])

    Enum.map(rows, fn [id] -> Ecto.UUID.load!(id) end)
  end

  defp owned(%{organization_id: organization_id}, :tenant),
    do: where(TenantObject, [m], m.organization_id == ^organization_id)

  defp owned(%{user_id: user_id}, :account),
    do: where(AccountObject, [m], m.user_id == ^user_id)

  defp normalize_result({:ok, row}), do: {:ok, normalize(row)}
  defp normalize_result({:error, changeset}), do: {:error, changeset}

  defp normalize(nil), do: nil

  defp normalize(%TenantObject{} = m),
    do: m |> base() |> Map.merge(%{scope: :tenant, owner_id: m.organization_id})

  defp normalize(%AccountObject{} = m),
    do: m |> base() |> Map.merge(%{scope: :account, owner_id: m.user_id})

  defp base(m) do
    %{
      id: m.id,
      purpose: m.purpose,
      object_key: m.object_key,
      content_type: m.content_type,
      byte_size: m.byte_size,
      width: m.width,
      height: m.height,
      status: m.status,
      attached_at: m.attached_at,
      inserted_at: m.inserted_at
    }
  end
end
