defmodule MilosTraining.Community.Ports.CommunityStore do
  @moduledoc """
  Persistence port for clubs, channels, posts and their reactions and
  comments (ADR-138), and for open clubs, member groups, the gym's community
  rules and reports (ADR-143).
  """

  @type context :: map()
  @type id :: binary()

  # Clubs and channels.
  @callback ensure_gym_club(context(), [map()]) :: {:ok, map()} | {:error, term()}
  @callback list_clubs(context(), [id()]) :: [map()]
  @callback get_club(context(), id()) :: map() | nil
  @callback get_channel(context(), id()) :: map() | nil
  @callback joined_channel_ids(context(), id(), [id()]) :: [id()]
  @callback join_channel(context(), map(), id(), String.t()) :: :ok | {:error, term()}
  @callback leave_channel(context(), map(), id()) :: :ok
  @callback suggested_channel_ids(context(), id(), [id()]) :: [id()]
  @callback ensure_context_channel(context(), map(), map()) :: {:ok, map()} | {:error, term()}
  @callback archive_context_channels(context(), id(), String.t(), [id()]) :: :ok
  @callback suggest_channel_members(context(), [{id(), id()}]) :: :ok
  @callback notify_levels(context(), id(), [id()]) :: %{id() => String.t()}
  @callback put_notify_level(context(), map(), id(), String.t()) ::
              {:ok, String.t()} | {:error, term()}

  # Open clubs (ADR-143).
  @callback create_club(context(), map(), [map()]) :: {:ok, map()} | {:error, term()}
  @callback update_club(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_clubs_by_ids(context(), [id()]) :: [map()]
  @callback list_open_clubs(context(), map()) :: [map()]
  @callback open_club_member_counts(context(), [id()]) :: %{id() => non_neg_integer()}
  @callback club_memberships_of(context(), id()) :: [map()]
  @callback list_club_memberships(context(), id(), String.t() | nil) :: [map()]
  @callback get_club_membership(context(), id(), id()) :: map() | nil
  @callback put_club_membership(context(), map(), id(), map()) :: {:ok, map()} | {:error, term()}
  @callback delete_club_membership(context(), id(), id()) :: :ok

  # Member groups (ADR-143).
  @callback get_community_settings(context()) :: map()
  @callback put_community_settings(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback create_group(context(), map(), map(), id(), String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback list_groups(context(), id(), map()) :: [map()]
  @callback update_group(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @callback update_group_lifecycle(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @callback channel_memberships_of(context(), id(), [id()]) :: %{id() => map()}
  @callback list_channel_memberships(context(), id()) :: [map()]
  @callback put_channel_membership(context(), map(), id(), map()) :: :ok | {:error, term()}
  @callback quiet_groups(context(), DateTime.t()) :: [map()]

  # Reports (ADR-143).
  @callback create_report(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_reports(context(), map()) :: [map()]
  @callback resolve_reports(context(), String.t(), id(), map()) :: non_neg_integer()
  @callback reported_ids(context(), id(), String.t()) :: [id()]
  @callback hide_comment(context(), id(), map()) :: :ok | {:error, term()}

  # Posts.
  @callback create_post(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback get_post(context(), id(), id()) :: map() | nil
  @callback list_posts(context(), map()) :: [map()]
  @callback list_pinned_posts(context(), [id()], id()) :: [map()]
  @callback list_public_posts(context(), [id()], id() | nil, map()) :: [map()]
  @callback moderate_post(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @doc """
  ADR-157: locks the post, hands its media view to `fun` and applies the
  `{:ok, attrs}` it returns (`:skip` changes nothing): `{:ok, before, after}`.
  """
  @callback update_post_media(context(), id(), (map() -> {:ok, map()} | :skip)) ::
              {:ok, map(), map()} | {:error, term()}
  @callback react(context(), map(), id(), String.t()) :: :ok | {:error, term()}
  @callback unreact(context(), map(), id(), String.t()) :: :ok
  @callback list_comments(context(), id()) :: [map()]
  @callback get_comment(context(), id()) :: map() | nil
  @callback add_comment(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback delete_comment(context(), id(), DateTime.t()) :: :ok | {:error, term()}
end
