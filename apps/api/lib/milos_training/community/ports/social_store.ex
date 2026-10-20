defmodule MilosTraining.Community.Ports.SocialStore do
  @moduledoc """
  Persistence port for follows and profile posts (ADR-142). Both are
  account-scoped: the follower or the author owns the row, and RLS decides
  who else reads it.
  """

  @type context :: map()
  @type id :: binary()
  @type page :: %{
          optional(:before) => {DateTime.t(), id()} | nil,
          optional(:limit) => pos_integer() | :all,
          optional(:among) => [id()]
        }

  # Follows.
  @callback get_follow(context(), id(), String.t(), id()) :: map() | nil
  @callback get_follow_by_id(context(), id()) :: map() | nil
  @callback insert_follow(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback delete_follow(context(), id(), String.t(), id()) :: :ok
  @callback accept_follow(context(), id(), DateTime.t()) :: {:ok, map()} | {:error, term()}
  @callback delete_follow_by_id(context(), id()) :: :ok | {:error, :not_found}
  @callback list_incoming(context(), String.t(), id(), String.t(), page()) :: [map()]
  @callback list_outgoing(context(), id(), [String.t()], [String.t()], page()) :: [map()]
  @callback count_incoming(context(), String.t(), id(), String.t()) :: non_neg_integer()
  @callback count_outgoing(context(), id(), [String.t()], [String.t()]) :: non_neg_integer()
  @callback active_target_ids(context(), id(), String.t()) :: [id()]
  @callback follow_statuses(context(), id(), String.t(), [id()]) :: %{id() => String.t()}
  @callback get_social_settings(context(), id()) :: map() | nil
  @callback put_social_settings(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @callback booking_sharer_ids(context()) :: [id()]
  @callback follower_counts(String.t(), [id()]) :: %{id() => non_neg_integer()}
  @callback following_count(id()) :: non_neg_integer()
  @callback hidden_member_ids([id()]) :: [id()]

  # Profile posts.
  @callback create_profile_post(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback get_profile_post(context(), id(), id() | nil) :: map() | nil
  @callback list_profile_posts(context(), map()) :: [map()]
  @callback count_profile_posts(context(), id()) :: non_neg_integer()
  @doc "ADR-157: as `CommunityStore.update_post_media/3`, for a profile post."
  @callback update_profile_post_media(context(), id(), (map() -> {:ok, map()} | :skip)) ::
              {:ok, map(), map()} | {:error, term()}
  @callback delete_profile_post(context(), id(), DateTime.t()) :: :ok | {:error, :not_found}
  @callback react_profile_post(context(), id(), id(), String.t()) :: :ok | {:error, term()}
  @callback unreact_profile_post(context(), id(), id(), String.t()) :: :ok
  @callback list_profile_comments(context(), id()) :: [map()]
  @callback get_profile_comment(context(), id()) :: map() | nil
  @callback add_profile_comment(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback delete_profile_comment(context(), id(), DateTime.t()) :: :ok | {:error, :not_found}
end
