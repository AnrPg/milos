defmodule MilosTraining.Community.Domain.TenantDataPolicy do
  @moduledoc """
  Community tenant data retention and purge policy (ADR-117, ADR-138).

  Declares the tables this context owns, in delete (dependency) order.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "community",
            purge_order: 15,
            disposition: :purge,
            basis:
              "Clubs, channels, posts, reactions and comments are social content of the gym's members with no retention obligation; deleted once exported.",
            tables: [
              %{table: "community_post_comments"},
              %{table: "community_post_reactions"},
              %{table: "community_posts"},
              %{table: "community_channel_memberships"},
              %{table: "community_club_memberships"},
              %{table: "community_channels"},
              %{table: "community_clubs"}
            ]
          })

  def policy, do: @policy
end
