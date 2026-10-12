defmodule MilosTraining.Content.ContentStore do
  @moduledoc false
  @behaviour MilosTraining.Content.Ports.ContentStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :content_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def list_videos(context, opts), do: tenant_call(context, :list_videos, [opts])

  @impl true
  def get_video(context, id), do: tenant_call(context, :get_video, [id])

  @impl true
  def create_video(context, params), do: tenant_call(context, :create_video, [params])

  @impl true
  def update_video(context, id, params), do: tenant_call(context, :update_video, [id, params])

  @impl true
  def set_video_published(context, id, published?),
    do: tenant_call(context, :set_video_published, [id, published?])

  @impl true
  def archive_video(context, id), do: tenant_call(context, :archive_video, [id])
end
