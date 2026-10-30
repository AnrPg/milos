defmodule Palee.Partners.Verifications do
  @moduledoc """
  Public API of the verification part of the Partners context (ADR-280):
  who may take part (a membership, or two sponsors and a check by the Palee
  team), the sponsors' quota and penalty, the SMS code and the selfie
  check. Rows are personal; every call names its session (`%{user_id: id}`
  for the person or a vendor, `:system` for jobs). Use cases live in
  `Palee.Application` (`PartnerEligibility`, `PartnerVerification`,
  `PartnerSponsoring`, `PlatformPartnerVerifications`,
  `PartnerVerificationRetention`).
  """

  alias Palee.Partners.VerificationStore

  alias Palee.Partners.Domain.{
    Eligibility,
    PhoneCodePolicy,
    SponsorPolicy,
    VerificationReviewPolicy
  }

  # Sessions.
  defdelegate run(scope, fun), to: VerificationStore
  defdelegate transaction(scope, fun), to: VerificationStore

  # Eligibility.
  defdelegate status(verification, request, vouches), to: Eligibility
  defdelegate verified?(verification), to: Eligibility
  defdelegate require_verified(verification), to: Eligibility
  defdelegate check_can_apply(verification, request), to: Eligibility
  def eligibility_steps, do: Eligibility.steps()
  def eligibility_statuses, do: Eligibility.statuses()

  # Sponsors.
  def sponsors_required, do: SponsorPolicy.required()
  def sponsor_quota, do: SponsorPolicy.quota()
  def sponsor_quota_days, do: SponsorPolicy.quota_days()
  def sponsor_penalty_days, do: SponsorPolicy.penalty_days()
  def link_minutes, do: SponsorPolicy.link_minutes()
  def sponsorship_statuses, do: SponsorPolicy.statuses()
  def sponsorship_channels, do: SponsorPolicy.channels()
  def vouch_decisions, do: SponsorPolicy.decisions()
  defdelegate quota_window_start(now), to: SponsorPolicy
  defdelegate penalty_until(now), to: SponsorPolicy
  defdelegate extend_penalty(current, until), to: SponsorPolicy
  defdelegate quota_left(vouches), to: SponsorPolicy
  defdelegate vouch_count(sponsorships), to: SponsorPolicy
  defdelegate check_sponsor(standing, sponsor_id, candidate_id, blocked?, now),
    to: SponsorPolicy,
    as: :check

  defdelegate sponsor_reason(standing, sponsor_id, candidate_id, blocked?, now),
    to: SponsorPolicy,
    as: :reason

  defdelegate membership_verified?(standing), to: SponsorPolicy
  defdelegate penalized?(standing, now), to: SponsorPolicy
  defdelegate normalize_vouch_decision(decision), to: SponsorPolicy, as: :normalize_decision
  defdelegate answer_sponsorship(sponsorship, decision, now), to: SponsorPolicy, as: :answer
  defdelegate ask_sponsor(existing, now), to: SponsorPolicy, as: :ask
  defdelegate cancel_sponsorship(sponsorship), to: SponsorPolicy, as: :cancel
  defdelegate link_expires_at(now), to: SponsorPolicy
  defdelegate link_digest(token), to: SponsorPolicy
  defdelegate normalize_link_token(token), to: SponsorPolicy, as: :normalize_token
  defdelegate check_link(link, sponsor_id, now), to: SponsorPolicy

  # Phone.
  def code_minutes, do: PhoneCodePolicy.code_minutes()
  def code_max_attempts, do: PhoneCodePolicy.max_attempts()
  defdelegate normalize_phone(phone), to: PhoneCodePolicy, as: :normalize
  defdelegate mask_phone(phone), to: PhoneCodePolicy, as: :mask
  defdelegate code_from(random), to: PhoneCodePolicy
  defdelegate normalize_code(code), to: PhoneCodePolicy
  defdelegate code_expires_at(now), to: PhoneCodePolicy, as: :expires_at
  defdelegate send_windows(now), to: PhoneCodePolicy
  defdelegate check_send_rate(last_hour, last_day), to: PhoneCodePolicy
  defdelegate check_code(code, now), to: PhoneCodePolicy
  defdelegate sms_body(code), to: PhoneCodePolicy
  defdelegate code_retention_cutoff(now), to: PhoneCodePolicy, as: :retention_cutoff

  # The Palee check.
  def selfie_content_types, do: VerificationReviewPolicy.content_types()
  def selfie_max_bytes, do: VerificationReviewPolicy.max_bytes()
  def selfie_probe_bytes, do: VerificationReviewPolicy.probe_bytes()
  def selfie_retention_days, do: VerificationReviewPolicy.retention_days()
  def request_statuses, do: VerificationReviewPolicy.statuses()
  def review_decisions, do: VerificationReviewPolicy.decisions()
  defdelegate request_open?(request), to: VerificationReviewPolicy, as: :open?
  defdelegate check_editable(request), to: VerificationReviewPolicy
  defdelegate selfie_code_from(random), to: VerificationReviewPolicy
  defdelegate new_request(user_id, selfie_code, now), to: VerificationReviewPolicy
  defdelegate validate_selfie_upload(content_type), to: VerificationReviewPolicy, as: :validate_upload
  defdelegate selfie_key(user_id, request_id, extension), to: VerificationReviewPolicy

  defdelegate selfie_content_type(key, user_id, request_id), to: VerificationReviewPolicy

  defdelegate validate_selfie_file(content_type, head, byte_size),
    to: VerificationReviewPolicy,
    as: :validate_file

  defdelegate missing_steps(request, vouches), to: VerificationReviewPolicy, as: :missing
  defdelegate check_submittable(request, vouches), to: VerificationReviewPolicy
  defdelegate submit_changes(key, now), to: VerificationReviewPolicy
  defdelegate selfie_expires_at(uploaded_at), to: VerificationReviewPolicy
  defdelegate selfie_retention_cutoff(now), to: VerificationReviewPolicy, as: :retention_cutoff
  defdelegate selfie_expired?(request, now), to: VerificationReviewPolicy
  defdelegate expire_changes(), to: VerificationReviewPolicy
  defdelegate withdraw_changes(), to: VerificationReviewPolicy
  defdelegate normalize_review_decision(params), to: VerificationReviewPolicy, as: :normalize_decision
  defdelegate check_decidable(request), to: VerificationReviewPolicy
  defdelegate decision_changes(decision, reason, actor_id, now), to: VerificationReviewPolicy

  # Store.
  defdelegate get_verification(scope, user_id), to: VerificationStore
  defdelegate verify_by_membership(scope), to: VerificationStore
  defdelegate verification_badges(scope, ids), to: VerificationStore
  defdelegate sponsor_standing(scope, ids, since), to: VerificationStore
  defdelegate insert_verification(scope, attrs), to: VerificationStore
  defdelegate update_verification(scope, verification, changes), to: VerificationStore
  defdelegate list_verifications(scope, ids), to: VerificationStore
  defdelegate get_request(scope, id), to: VerificationStore
  defdelegate latest_request(scope, user_id), to: VerificationStore
  defdelegate create_request(scope, attrs), to: VerificationStore
  defdelegate update_request(scope, request, changes), to: VerificationStore
  defdelegate list_requests(scope, status, limit), to: VerificationStore
  defdelegate requests_with_selfies_before(scope, cutoff), to: VerificationStore
  defdelegate requests_of(scope, user_id), to: VerificationStore
  defdelegate count_codes_since(scope, user_id, since), to: VerificationStore
  defdelegate insert_code(scope, attrs), to: VerificationStore
  defdelegate latest_code(scope, request_id), to: VerificationStore
  defdelegate update_code(scope, code, changes), to: VerificationStore
  defdelegate delete_code(scope, code), to: VerificationStore
  defdelegate delete_codes_before(scope, cutoff), to: VerificationStore
  defdelegate get_sponsorship(scope, id), to: VerificationStore
  defdelegate sponsorship_between(scope, candidate_id, sponsor_id), to: VerificationStore
  defdelegate sponsorships_of_candidate(scope, candidate_id), to: VerificationStore
  defdelegate sponsorships_of_sponsor(scope, sponsor_id, statuses), to: VerificationStore
  defdelegate count_vouches_since(scope, sponsor_id, since), to: VerificationStore
  defdelegate insert_sponsorship(scope, attrs), to: VerificationStore
  defdelegate update_sponsorship(scope, sponsorship, changes), to: VerificationStore
  defdelegate delete_open_sponsorships(scope, candidate_id), to: VerificationStore
  defdelegate vouched_sponsor_ids(scope, candidate_id), to: VerificationStore
  defdelegate insert_link(scope, attrs), to: VerificationStore
  defdelegate delete_links(scope, candidate_id), to: VerificationStore
  defdelegate find_link(scope, digest), to: VerificationStore
  defdelegate redeem_link(scope, digest, now), to: VerificationStore
  defdelegate purge_person(scope, user_id), to: VerificationStore
end
