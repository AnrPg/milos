defmodule Palee.Community.Domain.TenantDataPolicy do
  @moduledoc """
  Community tenant data retention and purge policy (ADR-117, ADR-138, ADR-143, ADR-153).

  Declares the tables this context owns, in delete (dependency) order.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "community",
            purge_order: 15,
            disposition: :purge,
            basis:
              "Clubs, channels, posts, reactions, comments, reports, events and their attendees, co-hosts and aggregated views (ADR-185) and the gym's community rules are social content of the gym's members with no retention obligation; deleted once exported.",
            tables: [
              %{table: "community_reports"},
              %{table: "community_event_view_marks"},
              %{table: "community_event_view_days"},
              %{table: "community_event_cohosts"},
              %{table: "community_event_attendees"},
              %{table: "community_events"},
              %{table: "community_post_comments"},
              %{table: "community_post_reactions"},
              %{table: "community_posts"},
              %{table: "community_channel_memberships"},
              %{table: "community_club_memberships"},
              %{table: "community_channels"},
              %{table: "community_clubs"},
              %{table: "community_settings"}
            ]
          })

  def policy, do: @policy
end
