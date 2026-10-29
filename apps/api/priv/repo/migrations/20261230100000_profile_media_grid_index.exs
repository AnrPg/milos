defmodule Palee.Repo.Migrations.ProfileMediaGridIndex do
  @moduledoc """
  ADR-231: the profile's «Πολυμέσα» grid pages through one person's posts
  that carry photos or a video, newest first. A partial index keeps that read
  from walking past their text-only posts.
  """

  use Ecto.Migration

  def change do
    create index(:community_profile_posts, [:user_id, :inserted_at, :id],
             where: "deleted_at IS NULL AND cardinality(media) > 0",
             name: :community_profile_posts_media_grid_index
           )
  end
end
