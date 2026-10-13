defmodule MilosTraining.Infrastructure.Content.EctoContentStore do
  @moduledoc "Ecto adapter of the Content store (ADR-098)."

  @behaviour MilosTraining.Content.Ports.ContentStore

  import Ecto.Query

  alias MilosTraining.Content.Video
  alias MilosTraining.Repo

  @impl true
  def list_videos(%{organization_id: organization_id}, opts) do
    Video
    |> where([video], video.organization_id == ^organization_id)
    |> filter_visibility(Keyword.get(opts, :visibility, :all))
    |> order_by([video], desc_nulls_last: video.published_at, desc: video.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def get_video(%{organization_id: organization_id}, id) do
    case fetch(organization_id, id) do
      nil -> nil
      video -> normalize(video)
    end
  end

  @impl true
  def create_video(%{organization_id: organization_id}, params) do
    params
    |> string_keys()
    |> Map.put("organization_id", organization_id)
    |> Video.create_changeset()
    |> Repo.insert()
    |> result()
  end

  @impl true
  def update_video(%{organization_id: organization_id}, id, params) do
    with_video(organization_id, id, fn video ->
      video |> Video.update_changeset(string_keys(params)) |> Repo.update() |> result()
    end)
  end

  @impl true
  def set_video_published(%{organization_id: organization_id}, id, published?) do
    with_video(organization_id, id, fn video ->
      published_at = if published?, do: video.published_at || DateTime.utc_now()
      video |> Video.publication_changeset(published_at) |> Repo.update() |> result()
    end)
  end

  @impl true
  def archive_video(%{organization_id: organization_id}, id) do
    with_video(organization_id, id, fn video ->
      video
      |> Video.archive_changeset(video.archived_at || DateTime.utc_now())
      |> Repo.update()
      |> result()
    end)
  end

  defp filter_visibility(query, :members) do
    where(query, [video], not is_nil(video.published_at) and is_nil(video.archived_at))
  end

  defp filter_visibility(query, :active), do: where(query, [video], is_nil(video.archived_at))
  defp filter_visibility(query, _all), do: query

  defp with_video(organization_id, id, fun) do
    case fetch(organization_id, id) do
      nil -> {:error, :not_found}
      video -> fun.(video)
    end
  end

  defp fetch(organization_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get_by(Video, id: id, organization_id: organization_id)
      :error -> nil
    end
  end

  defp result({:ok, video}), do: {:ok, normalize(video)}
  defp result({:error, changeset}), do: {:error, changeset}

  defp normalize(%Video{} = video) do
    %{
      id: video.id,
      title: video.title,
      description: video.description,
      video_url: video.video_url,
      duration_minutes: video.duration_minutes,
      tags: video.tags || [],
      published_at: video.published_at,
      archived_at: video.archived_at,
      inserted_at: video.inserted_at,
      updated_at: video.updated_at
    }
  end

  defp string_keys(params), do: Map.new(params, fn {key, value} -> {to_string(key), value} end)
end
