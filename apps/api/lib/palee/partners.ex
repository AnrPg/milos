defmodule Palee.Partners do
  @moduledoc """
  Partners bounded context (ADR-169, ADR-280, vision §7.3): training
  partners across Palee. A verified person keeps one account-level profile,
  swipes one public deck of other verified people nearby, and a mutual like
  makes a match with its own conversation and «Κλείστε μαζί» plans.

  Rows are personal, not a gym's. Who may take part is the verification
  side's word (`Palee.Application.PartnerEligibility`); blocking is
  Community's (it applies to a person, not to Partners). Use cases live in
  `Palee.Application` (`Partners`, `PartnerMatches`).
  """

  alias Palee.Partners.PartnerStore

  alias Palee.Partners.Domain.{
    BadgePolicy,
    DeckPolicy,
    MatchPolicy,
    MessagePolicy,
    ProfilePolicy,
    ReportPolicy,
    SwipePolicy
  }

  # Profiles.
  def levels, do: ProfilePolicy.levels()
  def times, do: ProfilePolicy.times()
  def goals, do: ProfilePolicy.goals()
  def genders, do: ProfilePolicy.genders()
  def gender_preferences, do: ProfilePolicy.gender_preferences()
  def max_goals, do: ProfilePolicy.max_goals()
  def max_disciplines, do: ProfilePolicy.max_disciplines()
  def about_max, do: ProfilePolicy.about_max()

  defdelegate normalize_profile(params, current \\ nil, disciplines \\ []),
    to: ProfilePolicy,
    as: :normalize

  defdelegate adult_confirmation(current, params, now), to: ProfilePolicy
  defdelegate profile_live?(profile), to: ProfilePolicy, as: :live?
  defdelegate pause_changes(profile, visible, now), to: ProfilePolicy

  # The deck.
  def deck_page_size, do: DeckPolicy.page_size()
  def pass_cooldown_days, do: DeckPolicy.pass_cooldown_days()
  def distances_km, do: DeckPolicy.distances_km()
  def default_within_km, do: DeckPolicy.default_within_km()
  defdelegate deck_filters(params), to: DeckPolicy, as: :filters
  defdelegate swiped_ids(swipes, now), to: DeckPolicy
  defdelegate deck(viewer, candidates, excluded, filters), to: DeckPolicy
  defdelegate swipeable?(viewer, other, excluded), to: DeckPolicy
  defdelegate shared(viewer, other), to: DeckPolicy

  # Badges.
  def badge_kinds, do: BadgePolicy.kinds()
  defdelegate badge(verification, show_box), to: BadgePolicy

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
  defdelegate can_message?(match), to: MatchPolicy
  defdelegate read_only?(match), to: MatchPolicy

  # Messages.
  def message_body_max, do: MessagePolicy.body_max()
  def plan_kinds, do: MessagePolicy.plan_kinds()
  defdelegate normalize_message_body(body), to: MessagePolicy, as: :normalize_body
  defdelegate normalize_note(body), to: MessagePolicy
  defdelegate message_page_limit(value), to: MessagePolicy, as: :page_limit
  defdelegate decode_message_cursor(cursor), to: MessagePolicy, as: :decode_cursor
  defdelegate message_page(rows, limit), to: MessagePolicy, as: :page
  defdelegate plan_snapshot(plan), to: MessagePolicy

  # Reports.
  def report_reasons, do: ReportPolicy.reasons()
  def report_statuses, do: ReportPolicy.statuses()
  def report_decisions, do: ReportPolicy.decisions()
  def report_note_max, do: ReportPolicy.note_max()
  defdelegate normalize_report(reporter_id, params), to: ReportPolicy, as: :normalize
  defdelegate normalize_report_decision(params), to: ReportPolicy, as: :normalize_decision

  defdelegate report_decision_changes(report, decision, by, note, now),
    to: ReportPolicy,
    as: :decision_changes

  defdelegate report_suspends?(decision), to: ReportPolicy, as: :suspends?
  defdelegate suspension_profile_changes(), to: ReportPolicy
  defdelegate suspension_end_reason(), to: ReportPolicy

  # Store.
  defdelegate get_profile(context, user_id), to: PartnerStore
  defdelegate get_profiles(context, user_ids), to: PartnerStore
  defdelegate list_live_profiles(context, excluded_ids), to: PartnerStore
  defdelegate create_profile(context, attrs), to: PartnerStore
  defdelegate update_profile(context, profile, changes), to: PartnerStore
  defdelegate list_swipes_by(context, swiper_id), to: PartnerStore
  defdelegate count_swipes_since(context, swiper_id, since), to: PartnerStore
  defdelegate record_swipe(context, attrs, mutual?, now), to: PartnerStore
  defdelegate delete_swipe(context, swiper_id, target_id), to: PartnerStore
  defdelegate get_match(context, id), to: PartnerStore
  defdelegate list_matches(context, user_id), to: PartnerStore
  defdelegate active_match_between(context, a, b), to: PartnerStore
  defdelegate active_partner_ids(context, user_id), to: PartnerStore
  defdelegate update_match(context, match, changes), to: PartnerStore
  defdelegate end_matches(context, filter, changes), to: PartnerStore
  defdelegate list_messages(context, match_id, cursor, limit), to: PartnerStore
  defdelegate insert_message(context, attrs, now), to: PartnerStore
  defdelegate unread_counts(context, user_id, matches), to: PartnerStore
  defdelegate insert_report(context, attrs), to: PartnerStore
  defdelegate get_report(context, id), to: PartnerStore
  defdelegate list_reports(context, status), to: PartnerStore
  defdelegate decide_reports(context, target_id, changes), to: PartnerStore
end
