defmodule MilosTraining.Partners.Ports.PartnerStore do
  @moduledoc """
  Persistence port of the Partners context (ADR-169). Every call runs in a
  session of the club's gym (`organization_id` of the club, the acting
  `user_id`); the gym's tenant policy is the outer wall, the queries name
  the people explicitly.
  """

  alias MilosTraining.Partners.{Match, Message, Profile, Swipe}

  @type context :: map()
  @type id :: Ecto.UUID.t()

  # Profiles.
  @callback get_profile(context, club_id :: id, user_id :: id) :: Profile.t() | nil
  @callback get_profile_by_id(context, id) :: Profile.t() | nil
  @callback list_profiles_of(context, user_id :: id) :: [Profile.t()]
  @callback list_live_profiles(context, club_id :: id, user_ids :: [id]) :: [Profile.t()]
  @callback create_profile(context, attrs :: map()) :: {:ok, Profile.t()} | {:error, term()}
  @callback update_profile(context, Profile.t(), changes :: map()) ::
              {:ok, Profile.t()} | {:error, term()}
  @callback set_active_for_user(context, user_id :: id, active :: boolean()) :: non_neg_integer()

  # Swipes.
  @callback list_swipes_by(context, club_id :: id, swiper_id :: id) :: [Swipe.t()]
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
  @callback delete_swipe(context, club_id :: id, swiper_id :: id, target_id :: id) ::
              non_neg_integer()

  # Matches.
  @callback get_match(context, id) :: Match.t() | nil
  @callback list_matches(context, user_id :: id) :: [Match.t()]
  @callback active_match_between(context, a :: id, b :: id) :: Match.t() | nil
  @callback active_partner_ids(context, user_id :: id) :: [id]
  @callback update_match(context, Match.t(), changes :: map()) ::
              {:ok, Match.t()} | {:error, term()}
  @callback end_matches(context, filter :: map(), changes :: map()) :: [Match.t()]

  # Messages.
  @callback list_messages(context, match_id :: id, cursor :: map() | nil, limit :: pos_integer()) ::
              [Message.t()]
  @callback insert_message(context, attrs :: map(), DateTime.t()) ::
              {:ok, Message.t()} | {:error, term()}
  @callback unread_counts(context, user_id :: id, [Match.t()]) :: %{id => non_neg_integer()}
end
