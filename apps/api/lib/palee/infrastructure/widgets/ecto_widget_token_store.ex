defmodule Palee.Infrastructure.Widgets.EctoWidgetTokenStore do
  @moduledoc "Ecto adapter of the widget token port (ADR-173); owner RLS, always filtered by the person too."

  @behaviour Palee.Widgets.Ports.WidgetTokenStore

  import Ecto.Query

  alias Palee.Repo
  alias Palee.Widgets.WidgetToken

  @impl true
  def create_widget_token(attrs) do
    case attrs |> WidgetToken.changeset() |> Repo.insert() do
      {:ok, row} -> {:ok, normalize(row)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def get_widget_token(user_id, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %WidgetToken{} = row <- Repo.get_by(WidgetToken, id: id, user_id: user_id) do
      normalize(row)
    else
      _missing -> nil
    end
  end

  @impl true
  def delete_widget_token(user_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        WidgetToken
        |> where([row], row.user_id == ^user_id and row.id == ^id)
        |> Repo.delete_all()
        |> elem(0)
        |> Kernel.>(0)

      :error ->
        false
    end
  end

  @impl true
  def delete_widget_tokens_beyond(user_id, keep) do
    kept =
      WidgetToken
      |> where([row], row.user_id == ^user_id)
      |> order_by([row], desc: row.inserted_at, desc: row.id)
      |> limit(^keep)
      |> select([row], row.id)

    WidgetToken
    |> where([row], row.user_id == ^user_id and row.id not in subquery(kept))
    |> Repo.delete_all()
    |> elem(0)
  end

  defp normalize(%WidgetToken{} = row),
    do: %{id: row.id, user_id: row.user_id, platform: row.platform, inserted_at: row.inserted_at}
end
