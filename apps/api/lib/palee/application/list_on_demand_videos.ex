defmodule Palee.Application.ListOnDemandVideos do
  @moduledoc "Published on-demand videos for clients whose package includes them (ADR-098)."

  alias Palee.Application.AuthorizePackageFeature
  alias Palee.Content

  def call(context, actor) do
    with :ok <- AuthorizePackageFeature.call(context, actor, :watch_on_demand) do
      {:ok, Content.list_videos(context, visibility: :members)}
    end
  end
end
