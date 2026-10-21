defmodule Palee.Buddies do
  @moduledoc """
  Buddies bounded context (ADR-160, vision §7.8, Εγώ › Buddy για στήριξη):
  one or two trusted people with mutual acceptance, «Χρειάζομαι στήριξη»
  with quick replies, quiet hours, the no-reply card, the optional weekly
  counts summary for buddies, and the member's grants of a weekly wellness
  summary to their coaches. Everything is the person's own (account-scoped).
  Buddies receive only what the member explicitly sends: never a craving's
  intensity, causes, outcome or notes.

  Use cases live in `Palee.Application` (`Buddies`,
  `SupportRequests`, `BuddyWeeklySummaries`, `WellnessSummarySharing`).
  M11's Λιγούρα reaches this context through the
  `Palee.Application.Ports.SupportRequests` port, or directly with
  `Palee.Application.SupportRequests.request_support/3`.
  """

  alias Palee.Buddies.BuddyStore

  alias Palee.Buddies.Domain.{
    Eligibility,
    InviteToken,
    LinkPolicy,
    MessagePolicy,
    QuietHours,
    SettingsPolicy,
    SummarySharingPolicy,
    SupportPolicy,
    TenantDataPolicy,
    WeeklySummary
  }

  def with_context(context, fun) when is_function(fun, 0),
    do: BuddyStore.with_context(context, fun)

  # Links.
  defdelegate link_statuses(), to: LinkPolicy, as: :statuses
  defdelegate max_buddies(), to: LinkPolicy
  defdelegate invite_days(), to: LinkPolicy
  defdelegate invite_expires_at(now), to: LinkPolicy, as: :expires_at
  defdelegate effective_status(link, now), to: LinkPolicy
  defdelegate open_link?(link, now), to: LinkPolicy, as: :open?
  defdelegate link_role(link, user_id), to: LinkPolicy, as: :role
  defdelegate other_party(link, user_id), to: LinkPolicy, as: :other
  defdelegate check_limit(links, now), to: LinkPolicy
  defdelegate transition(link, action, role, now), to: LinkPolicy
  defdelegate can_set_summary?(link, user_id, now), to: LinkPolicy

  # Who can be asked.
  defdelegate relations(), to: Eligibility
  defdelegate check_eligibility(inviter_id, invitee_id, relation), to: Eligibility, as: :check
  defdelegate search_term(term), to: Eligibility

  # Invite links.
  defdelegate generate_invite_token(), to: InviteToken, as: :generate
  defdelegate invite_token_digest(token), to: InviteToken, as: :digest
  defdelegate decode_invite_token(token), to: InviteToken, as: :decode
  defdelegate invite_path(token), to: InviteToken, as: :path

  # Settings.
  defdelegate default_tz(), to: SettingsPolicy
  defdelegate settings_changes(current, params, valid_zone?), to: SettingsPolicy, as: :changes
  defdelegate present_settings(settings), to: SettingsPolicy, as: :present
  defdelegate hhmm(time), to: SettingsPolicy
  defdelegate quiet_delivery(hours, now), to: QuietHours, as: :delivery

  def settings(context, user_id),
    do: context |> BuddyStore.get_settings(user_id) |> SettingsPolicy.effective()

  # Support requests.
  defdelegate support_message_max(), to: SupportPolicy, as: :message_max
  defdelegate support_sources(), to: SupportPolicy, as: :sources
  defdelegate reply_kinds(), to: SupportPolicy
  defdelegate quick_replies(), to: SupportPolicy
  defdelegate undo_seconds(), to: SupportPolicy
  defdelegate nudge_minutes(), to: SupportPolicy
  defdelegate rate_limit(), to: SupportPolicy
  defdelegate normalize_message(message), to: SupportPolicy
  defdelegate normalize_source(source), to: SupportPolicy
  defdelegate rate_window_start(now), to: SupportPolicy
  defdelegate check_rate(sent), to: SupportPolicy
  defdelegate check_buddies(buddies), to: SupportPolicy
  defdelegate undo_until(request), to: SupportPolicy
  defdelegate deliver_at(request), to: SupportPolicy
  defdelegate nudge_at(request), to: SupportPolicy
  defdelegate can_undo?(request, now), to: SupportPolicy
  defdelegate deliverable?(request), to: SupportPolicy
  defdelegate nudge(request, replies, now), to: SupportPolicy
  defdelegate nudge_needed?(request, replies, now), to: SupportPolicy
  defdelegate validate_reply(kind, text), to: SupportPolicy
  defdelegate can_reply?(request), to: SupportPolicy
  defdelegate phone_for(kind, phone), to: SupportPolicy

  # The pair's conversation.
  defdelegate message_body_max(), to: MessagePolicy, as: :body_max
  defdelegate normalize_message_body(body), to: MessagePolicy, as: :normalize_body
  defdelegate link_party?(link, user_id), to: MessagePolicy, as: :party?
  defdelegate can_post_message?(link, now), to: MessagePolicy, as: :can_post?
  defdelegate messages_read_only?(link, now), to: MessagePolicy, as: :read_only?
  defdelegate reply_message_body(kind, quick_text, text), to: MessagePolicy, as: :reply_body
  defdelegate message_page_limit(value), to: MessagePolicy, as: :page_limit
  defdelegate decode_message_cursor(cursor), to: MessagePolicy, as: :decode_cursor
  defdelegate message_page(rows, limit), to: MessagePolicy, as: :page

  # Weekly summaries.
  defdelegate summary_due?(tz, now), to: WeeklySummary, as: :due?
  defdelegate summary_week(tz, now), to: WeeklySummary, as: :week
  defdelegate previous_week(tz, now), to: WeeklySummary
  defdelegate compose_summary(week, cravings, support_requests), to: WeeklySummary, as: :compose
  defdelegate summary_dedupe_key(link_id, week_start), to: WeeklySummary, as: :dedupe_key
  defdelegate summary_scopes(), to: SummarySharingPolicy, as: :scopes
  defdelegate summary_toggles(grants), to: SummarySharingPolicy, as: :toggles
  defdelegate summary_changes(toggles, params), to: SummarySharingPolicy, as: :changes
  defdelegate coach_summary(week, toggles, week_line, cravings), to: SummarySharingPolicy

  # Tenant data lifecycle (ADR-117): only the coach-read audit is a gym's.
  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)

  # Store.
  defdelegate list_links(context, user_id, ended_since), to: BuddyStore
  defdelegate get_link(context, id), to: BuddyStore
  defdelegate create_link(context, attrs, guard), to: BuddyStore
  defdelegate update_link(context, link, changes), to: BuddyStore
  defdelegate expire_stale(context, user_id, now), to: BuddyStore
  defdelegate active_links_as_requester(context, user_id), to: BuddyStore
  defdelegate open_links_between(context, a, b), to: BuddyStore
  defdelegate relation(context, other_id), to: BuddyStore
  defdelegate candidates(context, term, limit), to: BuddyStore
  defdelegate invite_preview(token_hash, now), to: BuddyStore
  defdelegate claim_invite(context, token_hash, now), to: BuddyStore
  defdelegate quiet_hours(context, buddy_id), to: BuddyStore
  defdelegate shared_phone(context, requester_id), to: BuddyStore
  defdelegate summary_requesters(limit), to: BuddyStore
  defdelegate put_settings(context, user_id, changes), to: BuddyStore
  defdelegate create_request(context, attrs, deliveries, guard, window_start), to: BuddyStore
  defdelegate count_requests_between(context, user_id, from, to), to: BuddyStore
  defdelegate get_request(context, id), to: BuddyStore
  defdelegate list_requests(context, user_id, role, limit), to: BuddyStore
  defdelegate list_deliveries(context, request_ids), to: BuddyStore
  defdelegate list_replies(context, request_ids), to: BuddyStore
  defdelegate undo_request(context, id, now), to: BuddyStore
  defdelegate mark_delivered(context, id, now), to: BuddyStore
  defdelegate mark_nudged(context, id, now), to: BuddyStore
  defdelegate insert_reply(context, attrs, now), to: BuddyStore
  defdelegate list_messages(context, link_id, cursor, limit), to: BuddyStore
  defdelegate insert_message(context, attrs), to: BuddyStore
  defdelegate mark_messages_read(context, link_id, reader_id, now), to: BuddyStore
  defdelegate unread_counts(context, reader_id, link_ids), to: BuddyStore
  defdelegate record_wellness_access(context, attrs), to: BuddyStore
  defdelegate list_wellness_access(context, user_id, limit), to: BuddyStore
  defdelegate wellness_summary_members(limit), to: BuddyStore
  defdelegate wellness_summary_coaches(member_id), to: BuddyStore
  defdelegate list_summary_grants(context, user_id), to: BuddyStore
  defdelegate grant_summary(context, user_id, scope, now), to: BuddyStore
  defdelegate withdraw_summary(context, user_id, scope, now), to: BuddyStore
end
