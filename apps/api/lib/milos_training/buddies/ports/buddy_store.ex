defmodule MilosTraining.Buddies.Ports.BuddyStore do
  @moduledoc """
  Persistence port of the Buddies context (ADR-160). Every call that reads
  or writes a person's rows runs in their session (`RepoContext`); row
  security admits a link, delivery or reply to both of its people, and a
  support request to the buddies it was delivered to. Lookups across
  people go through narrow definer functions.
  """

  @type context :: map()
  @type link :: map()
  @type request :: map()

  # Links.
  @callback list_links(context(), user_id :: binary(), ended_since :: DateTime.t()) :: [link()]
  @callback get_link(context(), id :: binary()) :: link() | nil
  @callback create_link(context(), attrs :: map(), guard :: ([link()] -> :ok | {:error, term()})) ::
              {:ok, link()} | {:error, term()}
  @callback update_link(context(), link(), changes :: map()) :: {:ok, link()} | {:error, term()}
  @callback expire_stale(context(), user_id :: binary(), DateTime.t()) :: non_neg_integer()
  @callback active_links_as_requester(context(), user_id :: binary()) :: [link()]
  @callback open_links_between(context(), binary(), binary()) :: [link()]
  @callback relation(context(), other_id :: binary()) :: String.t() | nil
  @callback candidates(context(), term :: String.t() | nil, limit :: pos_integer()) ::
              [%{user_id: binary(), relation: String.t()}]
  @callback invite_preview(token_hash :: binary(), DateTime.t()) :: map() | nil
  @callback claim_invite(context(), token_hash :: binary(), DateTime.t()) :: binary() | nil
  @callback quiet_hours(context(), buddy_id :: binary()) :: map() | nil
  @callback shared_phone(context(), requester_id :: binary()) :: String.t() | nil
  @callback summary_requesters(limit :: pos_integer()) :: [%{user_id: binary(), tz: String.t()}]

  # Settings.
  @callback get_settings(context(), user_id :: binary()) :: map() | nil
  @callback put_settings(context(), user_id :: binary(), changes :: map()) ::
              {:ok, map()} | {:error, term()}

  # Support requests.
  @callback create_request(
              context(),
              attrs :: map(),
              deliveries :: [map()],
              guard :: (non_neg_integer() -> :ok | {:error, term()}),
              window_start :: DateTime.t()
            ) :: {:ok, request()} | {:error, term()}
  @callback count_requests_between(context(), binary(), DateTime.t(), DateTime.t()) ::
              non_neg_integer()
  @callback get_request(context(), id :: binary()) :: request() | nil
  @callback list_requests(
              context(),
              user_id :: binary(),
              role :: :sent | :received,
              limit :: pos_integer()
            ) ::
              [request()]
  @callback list_deliveries(context(), request_ids :: [binary()]) :: [map()]
  @callback list_replies(context(), request_ids :: [binary()]) :: [map()]
  @callback undo_request(context(), id :: binary(), DateTime.t()) :: non_neg_integer()
  @callback mark_delivered(context(), id :: binary(), DateTime.t()) :: non_neg_integer()
  @callback mark_nudged(context(), id :: binary(), DateTime.t()) :: non_neg_integer()
  @callback insert_reply(context(), attrs :: map(), DateTime.t()) ::
              {:ok, map()} | {:error, term()}

  # The pair's conversation (one thread per link).
  @callback list_messages(
              context(),
              link_id :: binary(),
              cursor :: map() | nil,
              limit :: pos_integer()
            ) :: [map()]
  @callback insert_message(context(), attrs :: map()) :: {:ok, map()} | {:error, term()}
  @callback mark_messages_read(
              context(),
              link_id :: binary(),
              reader_id :: binary(),
              DateTime.t()
            ) ::
              non_neg_integer()
  @callback unread_counts(context(), reader_id :: binary(), link_ids :: [binary()]) :: map()

  # The coach's wellness-summary reads and the Sunday push.
  @callback record_wellness_access(context(), attrs :: map()) :: :ok
  @callback list_wellness_access(context(), user_id :: binary(), limit :: pos_integer()) ::
              [map()]
  @callback wellness_summary_members(limit :: pos_integer()) ::
              [%{user_id: binary(), tz: String.t()}]
  @callback wellness_summary_coaches(member_id :: binary()) ::
              [%{organization_id: binary(), coach_user_id: binary()}]

  # The coach's weekly summary grants.
  @callback list_summary_grants(context(), user_id :: binary()) :: [map()]
  @callback grant_summary(context(), user_id :: binary(), scope :: String.t(), DateTime.t()) ::
              {:ok, map()}
  @callback withdraw_summary(context(), user_id :: binary(), scope :: String.t(), DateTime.t()) ::
              non_neg_integer()
end
