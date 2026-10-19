defmodule MilosTraining.Community.Ports.CommunityStore do
  @moduledoc "Persistence port for clubs, channels, posts and their reactions and comments (ADR-138)."

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

  # Posts.
  @callback create_post(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback get_post(context(), id(), id()) :: map() | nil
  @callback list_posts(context(), map()) :: [map()]
  @callback list_pinned_posts(context(), [id()], id()) :: [map()]
  @callback list_public_posts(context(), [id()], id() | nil, map()) :: [map()]
  @callback moderate_post(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @callback react(context(), map(), id(), String.t()) :: :ok | {:error, term()}
  @callback unreact(context(), map(), id(), String.t()) :: :ok
  @callback list_comments(context(), id()) :: [map()]
  @callback get_comment(context(), id()) :: map() | nil
  @callback add_comment(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback delete_comment(context(), id(), DateTime.t()) :: :ok | {:error, term()}
end
