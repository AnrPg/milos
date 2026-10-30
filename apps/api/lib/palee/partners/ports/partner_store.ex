defmodule Palee.Partners.Ports.PartnerStore do
  @moduledoc """
  Persistence port of the Partners deck (ADR-169, ADR-280): profiles,
  swipes, matches, messages and reports. Rows are personal, not a gym's:
  every call runs in the acting person's own session (`app.user_id`; the
  Palee team's for the reports queue), and row security admits a person's
  own rows, the live profiles of the deck and the two sides of a match.
  """

  alias Palee.Partners.{Match, Message, Profile, Report, Swipe}

  @type context :: map()
  @type id :: Ecto.UUID.t()

  # Profiles.
  @callback get_profile(context, user_id :: id) :: Profile.t() | nil
  @callback get_profiles(context, user_ids :: [id]) :: [Profile.t()]
  @doc "Every live profile (on, not paused) except those of `excluded_ids`."
  @callback list_live_profiles(context, excluded_ids :: [id]) :: [Profile.t()]
  @callback create_profile(context, attrs :: map()) :: {:ok, Profile.t()} | {:error, term()}
  @callback update_profile(context, Profile.t(), changes :: map()) ::
              {:ok, Profile.t()} | {:error, term()}

  # Swipes.
  @callback list_swipes_by(context, swiper_id :: id) :: [Swipe.t()]
  @callback count_swipes_since(context, swiper_id :: id, since :: DateTime.t()) ::
              non_neg_integer()
  @callback record_swipe(
              context,
              attrs :: map(),
              mutual? :: (Swipe.t() | nil -> boolean()),
              DateTime.t()
            ) ::
              {:ok, %{swipe: Swipe.t(), match: Match.t() | nil, new_match: boolean()}}
              | {:error, term()}
  @callback delete_swipe(context, swiper_id :: id, target_id :: id) :: non_neg_integer()

  # Matches.
  @callback get_match(context, id) :: Match.t() | nil
  @callback list_matches(context, user_id :: id) :: [Match.t()]
  @callback active_match_between(context, a :: id, b :: id) :: Match.t() | nil
  @callback active_partner_ids(context, user_id :: id) :: [id]
  @callback update_match(context, Match.t(), changes :: map()) ::
              {:ok, Match.t()} | {:error, term()}
  @doc "Ends the active matches of `%{pair: {a, b}}` or `%{user_id: id}`."
  @callback end_matches(context, filter :: map(), changes :: map()) :: [Match.t()]

  # Messages.
  @callback list_messages(context, match_id :: id, cursor :: map() | nil, limit :: pos_integer()) ::
              [Message.t()]
  @callback insert_message(context, attrs :: map(), DateTime.t()) ::
              {:ok, Message.t()} | {:error, term()}
  @callback unread_counts(context, user_id :: id, [Match.t()]) :: %{id => non_neg_integer()}

  # Reports.
  @doc "Files a report; a second open report of the same pair is `:already_reported`."
  @callback insert_report(context, attrs :: map()) ::
              {:ok, Report.t() | :already_reported} | {:error, term()}
  @callback get_report(context, id) :: Report.t() | nil
  @callback list_reports(context, status :: String.t()) :: [Report.t()]
  @doc "Closes every open report on `target_id` with the decision's changes."
  @callback decide_reports(context, target_id :: id, changes :: map()) :: [Report.t()]
end
