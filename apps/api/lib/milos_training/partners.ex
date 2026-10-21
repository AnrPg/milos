defmodule MilosTraining.Partners do
  @moduledoc """
  Partners bounded context (ADR-169, vision §7.3): training partners inside
  a club the gym verified. A member opts in per club with a short profile,
  swipes a deck of the club's other members who opted in, and a mutual like
  makes a match with its own conversation and «Κλείστε μαζί» plans.

  Rows are tenant data of the club's gym. Who belongs to a club is not
  stored here: use cases pass the club's current members on every read, so
  eligibility is always the gym's word. Blocking is Community's (it applies
  to a person, not to Partners); use cases live in `MilosTraining.Application`
  (`Partners`, `PartnerMatches`).
  """

  alias MilosTraining.Partners.PartnerStore

  alias MilosTraining.Partners.Domain.{
    ClubEligibility,
    DeckPolicy,
    MatchPolicy,
    MessagePolicy,
    ProfilePolicy,
    SessionPolicy,
    SwipePolicy,
    TenantDataPolicy
  }

  def with_context(context, fun) when is_function(fun, 0),
    do: PartnerStore.with_context(context, fun)

  # Clubs.
  defdelegate club_verified?(club), to: ClubEligibility, as: :verified?
  defdelegate check_club(club, gym_enabled?), to: ClubEligibility, as: :check
  defdelegate club_offered?(club, gym_enabled?), to: ClubEligibility, as: :offered?

  # Profiles.
  def levels, do: ProfilePolicy.levels()
  def times, do: ProfilePolicy.times()
  def goals, do: ProfilePolicy.goals()
  def genders, do: ProfilePolicy.genders()
  def gender_preferences, do: ProfilePolicy.gender_preferences()
  def max_goals, do: ProfilePolicy.max_goals()
  def about_max, do: ProfilePolicy.about_max()
  defdelegate normalize_profile(params, current \\ nil), to: ProfilePolicy, as: :normalize
  defdelegate check_activation(profile, active), to: ProfilePolicy
  defdelegate profile_live?(profile), to: ProfilePolicy, as: :live?

  # The deck.
  def deck_page_size, do: DeckPolicy.page_size()
  def pass_cooldown_days, do: DeckPolicy.pass_cooldown_days()
  defdelegate deck_filters(params), to: DeckPolicy, as: :filters
  defdelegate swiped_ids(swipes, now), to: DeckPolicy
  defdelegate deck(viewer, candidates, excluded, filters), to: DeckPolicy
  defdelegate swipeable?(viewer, other, excluded), to: DeckPolicy
  defdelegate shared(viewer, other), to: DeckPolicy

  # Swipes.
  def swipe_daily_limit, do: SwipePolicy.daily_limit()
  def swipe_directions, do: SwipePolicy.directions()
  defdelegate normalize_direction(direction), to: SwipePolicy
  defdelegate swipe_window_start(now), to: SwipePolicy, as: :window_start
  defdelegate check_swipe_rate(count), to: SwipePolicy, as: :check_rate
  defdelegate swipes_remaining(count), to: SwipePolicy, as: :remaining
  defdelegate mutual?(direction, reverse), to: SwipePolicy

  # Matches.
  def match_statuses, do: MatchPolicy.statuses()
  def end_reasons, do: MatchPolicy.end_reasons()
  defdelegate pair(a, b), to: MatchPolicy
  defdelegate match_party?(match, user_id), to: MatchPolicy, as: :party?
  defdelegate other_party(match, user_id), to: MatchPolicy, as: :other
  defdelegate match_active?(match), to: MatchPolicy, as: :active?
  defdelegate end_changes(match, reason, actor_id, now), to: MatchPolicy
  defdelegate read_field(match, user_id), to: MatchPolicy
  defdelegate read_at(match, user_id), to: MatchPolicy
  defdelegate can_message?(match, both_members?), to: MatchPolicy
  defdelegate read_only?(match, both_members?), to: MatchPolicy

  # Messages.
  def message_body_max, do: MessagePolicy.body_max()
  defdelegate normalize_message_body(body), to: MessagePolicy, as: :normalize_body
  defdelegate normalize_note(body), to: MessagePolicy
  defdelegate message_page_limit(value), to: MessagePolicy, as: :page_limit
  defdelegate decode_message_cursor(cursor), to: MessagePolicy, as: :decode_cursor
  defdelegate message_page(rows, limit), to: MessagePolicy, as: :page
  defdelegate plan_snapshot(slot), to: MessagePolicy

  # «Κλείστε μαζί».
  def session_window_days, do: SessionPolicy.window_days()
  defdelegate session_window(now), to: SessionPolicy, as: :window

  defdelegate session_suggestions(slots, pair_ids, shared_times, timezone, now),
    to: SessionPolicy,
    as: :suggestions

  # Tenant data lifecycle (ADR-117).
  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)

  # Store.
  defdelegate get_profile(context, club_id, user_id), to: PartnerStore
  defdelegate get_profile_by_id(context, id), to: PartnerStore
  defdelegate list_profiles_of(context, user_id), to: PartnerStore
  defdelegate profile_ids_for(context, pairs), to: PartnerStore
  defdelegate list_live_profiles(context, club_id, user_ids), to: PartnerStore
  defdelegate create_profile(context, attrs), to: PartnerStore
  defdelegate update_profile(context, profile, changes), to: PartnerStore
  defdelegate set_active_for_user(context, user_id, active), to: PartnerStore
  defdelegate list_swipes_by(context, club_id, swiper_id), to: PartnerStore
  defdelegate count_swipes_since(context, swiper_id, since), to: PartnerStore
  defdelegate record_swipe(context, attrs, mutual?, now), to: PartnerStore
  defdelegate delete_swipe(context, club_id, swiper_id, target_id), to: PartnerStore
  defdelegate get_match(context, id), to: PartnerStore
  defdelegate list_matches(context, user_id), to: PartnerStore
  defdelegate active_match_between(context, a, b), to: PartnerStore
  defdelegate active_partner_ids(context, user_id), to: PartnerStore
  defdelegate update_match(context, match, changes), to: PartnerStore
  defdelegate end_matches(context, filter, changes), to: PartnerStore
  defdelegate list_messages(context, match_id, cursor, limit), to: PartnerStore
  defdelegate insert_message(context, attrs, now), to: PartnerStore
  defdelegate unread_counts(context, user_id, matches), to: PartnerStore
end
