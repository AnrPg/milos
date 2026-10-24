defmodule Palee.Community.Ports.SocialStore do
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
          optional(:among) => [id()],
          optional(:except) => [id()]
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
  @doc "ADR-193 §2: accepts every request waiting for the person; answers how many."
  @callback accept_all_incoming(context(), id(), DateTime.t()) :: non_neg_integer()
  @doc "ADR-193 §1: the people the person and they follow each other actively."
  @callback buddy_ids(context(), id()) :: [id()]
  @doc "ADR-193: facts between the session user and each person (definer function)."
  @callback person_relations(context(), [id()]) :: %{id() => map()}
  @doc "ADR-193 §4: ranked people search for the session user, as `{id, relation}`."
  @callback search_people(context(), String.t(), String.t(), pos_integer()) :: [
              {id(), String.t()}
            ]
  @doc "ADR-193 §2: whether each person is public (definer function)."
  @callback public_user_ids([id()]) :: [id()]
  @callback follow_statuses(context(), id(), String.t(), [id()]) :: %{id() => String.t()}
  @callback get_social_settings(context(), id()) :: map() | nil
  @callback put_social_settings(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @callback booking_sharer_ids(context()) :: [id()]
  @callback follower_counts(String.t(), [id()]) :: %{id() => non_neg_integer()}
  @callback following_count(id()) :: non_neg_integer()
  @doc "ADR-193 §1: Buddies, followers only and following only (people), never overlapping."
  @callback follow_groups(id()) :: %{
              buddies: non_neg_integer(),
              followers_only: non_neg_integer(),
              following_only: non_neg_integer()
            }
  @callback hidden_member_ids([id()]) :: [id()]

  # Blocks (ADR-169 §5).
  @callback insert_block(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback delete_block(context(), id(), id()) :: :ok
  @callback list_blocks(context(), id()) :: [map()]
  @callback blocked_user_ids(context()) :: [id()]

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
