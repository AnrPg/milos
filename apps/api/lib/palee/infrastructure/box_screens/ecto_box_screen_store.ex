defmodule Palee.Infrastructure.BoxScreens.EctoBoxScreenStore do
  @moduledoc "Ecto adapter of the box screen store (ADR-253)."

  @behaviour Palee.BoxScreens.Ports.BoxScreenStore

  import Ecto.Query

  alias Palee.BoxScreens.BoxScreen
  alias Palee.Repo

  @touch_every_seconds 60

  @impl true
  def list(%{organization_id: organization_id}) do
    BoxScreen
    |> where([s], s.organization_id == ^organization_id)
    |> order_by([s], asc: s.inserted_at, asc: s.id)
    |> Repo.all()
    |> Enum.map(&to_map/1)
  end

  @impl true
  def count(%{organization_id: organization_id}) do
    BoxScreen
    |> where([s], s.organization_id == ^organization_id)
    |> Repo.aggregate(:count)
  end

  @impl true
  def get(%{organization_id: organization_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %BoxScreen{} = screen <- Repo.get_by(BoxScreen, id: id, organization_id: organization_id) do
      to_map(screen)
    else
      _missing -> nil
    end
  end

  @impl true
  def insert(%{organization_id: organization_id}, attrs) do
    %BoxScreen{organization_id: organization_id}
    |> BoxScreen.changeset(attrs)
    |> Repo.insert()
    |> result()
  end

  @impl true
  def update(%{organization_id: organization_id}, id, attrs) do
    case Repo.get_by(BoxScreen, id: id, organization_id: organization_id) do
      nil -> {:error, :box_screen_not_found}
      screen -> screen |> BoxScreen.changeset(attrs) |> Repo.update() |> result()
    end
  end

  @impl true
  def delete(%{organization_id: organization_id}, id) do
    case BoxScreen
         |> where([s], s.id == ^id and s.organization_id == ^organization_id)
         |> Repo.delete_all() do
      {1, _rows} -> :ok
      {0, _rows} -> {:error, :not_found}
    end
  end

  @impl true
  def find_pairing(hash, %DateTime{} = now) when is_binary(hash) do
    case Repo.query!(
           "SELECT organization_id, screen_id FROM palee_box_screen_pairing($1, $2)",
           [hash, now]
         ) do
      %{rows: [[organization_id, screen_id]]} ->
        {Ecto.UUID.load!(organization_id), Ecto.UUID.load!(screen_id)}

      _none ->
        nil
    end
  end

  @impl true
  def claim(%{organization_id: organization_id}, id, hash, %DateTime{} = now) do
    Repo.transaction(fn ->
      BoxScreen
      |> where([s], s.id == ^id and s.organization_id == ^organization_id)
      |> where([s], s.pairing_code_hash == ^hash and s.pairing_code_expires_at > ^now)
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> case do
        nil ->
          Repo.rollback(:invalid_pairing_code)

        screen ->
          screen
          |> Ecto.Changeset.change(%{
            pairing_code_hash: nil,
            pairing_code_expires_at: nil,
            token_version: screen.token_version + 1,
            paired_at: now,
            last_seen_at: now
          })
          |> Repo.update!()
          |> to_map()
      end
    end)
  end

  @impl true
  def touch(%{organization_id: organization_id}, id, %DateTime{} = now) do
    stale = DateTime.add(now, -@touch_every_seconds, :second)

    BoxScreen
    |> where([s], s.id == ^id and s.organization_id == ^organization_id)
    |> where([s], is_nil(s.last_seen_at) or s.last_seen_at < ^stale)
    |> Repo.update_all(set: [last_seen_at: now])

    :ok
  end

  defp result({:ok, screen}), do: {:ok, to_map(screen)}
  defp result({:error, %Ecto.Changeset{errors: errors}}), do: {:error, changeset_error(errors)}

  defp changeset_error(errors) do
    cond do
      Keyword.has_key?(errors, :location_id) -> :invalid_screen_branch
      Keyword.has_key?(errors, :name) -> :invalid_screen_name
      true -> :invalid_box_screen
    end
  end

  defp to_map(%BoxScreen{} = screen), do: screen |> Map.from_struct() |> Map.delete(:__meta__)
end
