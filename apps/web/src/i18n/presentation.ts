import { ApiError } from "@/api/client";

export type UiTranslator = (
  key: string,
  params?: Record<string, string | number | Date>,
) => string;

const SEMANTIC_KEYS: Record<string, string> = {
  admin: "semanticAdmin",
  member: "semanticMember",
  athlete: "semanticAthlete",
  active: "semanticActive",
  inactive: "semanticInactive",
  pending: "semanticPending",
  approved: "semanticApproved",
  rejected: "semanticRejected",
  cancelled: "semanticCancelled",
  completed: "semanticCompleted",
  upcoming: "semanticUpcoming",
  overdue: "semanticOverdue",
  paused: "semanticPaused",
  idle: "semanticIdle",
  open: "semanticOpen",
  reviewed: "semanticReviewed",
  archived: "semanticArchived",
  needs_follow_up: "semanticNeedsFollowUp",
  attended: "semanticAttended",
  missed: "semanticMissed",
  no_show: "semanticNoShow",
  late_cancel: "semanticLateCancel",
  accepted: "semanticAccepted",
  published: "semanticPublished",
  draft: "semanticDraft",
  crossfit: "semanticCrossfit",
  strength: "semanticStrength",
  gymnastics: "semanticGymnastics",
  aerobics: "semanticAerobics",
  flexibility: "semanticFlexibility",
  recovery: "semanticRecovery",
  beginner: "semanticBeginner",
  intermediate: "semanticIntermediate",
  advanced: "semanticAdvanced",
  base: "semanticBase",
  rx: "semanticRx",
  scaled: "semanticScaled",
  "rx+": "semanticRxPlus",
  self_selected: "semanticSelfSelected",
  class_booking: "semanticClassBooking",
  assigned: "semanticAssigned",
  direct: "semanticDirect",
  assignment: "semanticAssignment",
  class_slot: "semanticClassSlot",
  chat: "semanticChat",
  coaching_message: "semanticCoachingMessage",
  box_message: "semanticBoxMessage",
  box: "semanticBox",
  system: "semanticSystem",
  workout_count: "semanticWorkoutCount",
  workout_type_count: "semanticWorkoutTypeCount",
  pr_count: "semanticPrCount",
  custom: "semanticCustom",
  unlimited: "semanticUnlimited",
  "limited-visits": "semanticLimitedVisits",
  hybrid: "semanticHybrid",
  membership: "pkgTypeMembership",
  class_pack: "pkgTypeClassPack",
  drop_in: "pkgTypeDropIn",
  pt_pack: "pkgTypePtPack",
  add_on: "pkgTypeAddOn",
  shared: "pkgTypeShared",
  corporate: "pkgTypeCorporate",
  semiannual: "pkgBilling_semiannual",
  one_off: "pkgBilling_one_off",
  with_base: "pkgBilling_with_base",
  credit: "semanticCredit",
  discount: "semanticDiscount",
  free_period: "semanticFreePeriod",
  manual: "semanticManual",
  refund: "semanticRefund",
  payment_reversal: "semanticPaymentReversal",
  cash: "semanticCash",
  bank_transfer: "semanticBankTransfer",
  card_manual: "semanticManualCard",
  waiver_reversal: "semanticWaiverReversal",
  membership_package: "semanticMembershipPackage",
  manual_charge: "semanticManualCharge",
  adjustment: "semanticAdjustment",
  percent: "semanticPercent",
  fixed_amount: "semanticFixedAmount",
  public: "semanticPublic",
  private: "semanticPrivate",
  low: "semanticLow",
  medium: "semanticMedium",
  high: "semanticHigh",
  mild: "semanticMild",
  moderate: "semanticModerate",
  severe: "semanticSevere",
  positive: "semanticPositive",
  neutral: "semanticNeutral",
  negative: "semanticNegative",
  workout: "semanticWorkout",
  execution: "semanticExecution",
  exercise: "semanticExercise",
  gym_parameter: "semanticGymParameter",
  coaching_parameter: "semanticCoachingParameter",
  app: "semanticApp",
  general: "semanticGeneral",
  skipped: "semanticSkipped",
  weight_changed: "semanticWeightChanged",
  reps_changed: "semanticRepsChanged",
  time_changed: "semanticTimeChanged",
  other: "semanticOther",
  time: "semanticTime",
  reps: "semanticReps",
  sets: "semanticSets",
  weight: "semanticWeight",
  rounds: "semanticRounds",
  "rounds+reps": "semanticRoundsAndReps",
  load: "semanticLoad",
  kcal: "semanticKilocalories",
  kcals: "semanticKilocalories",
  hr_drop: "semanticHeartRateDrop",
  accumulated_work_time: "semanticAccumulatedWorkTime",
  pass_fail: "semanticPassFail",
  intervals_survived: "semanticIntervalsSurvived",
  mins_secs: "semanticMinutesSeconds",
  secs: "semanticSeconds",
  m: "semanticMetres",
  kg: "semanticKilograms",
  lb: "semanticPounds",
  bw: "semanticBodyweight",
  absolute: "semanticAbsolute",
  pct_1rm: "semanticPercentOneRepMax",
  linear: "semanticLinear",
  per_set: "semanticPerSet",
  none: "semanticNone",
  minute: "semanticMinute",
  zone: "semanticZone",
  per_kilometre: "semanticPerKilometre",
  odd_even: "semanticOddEven",
  emom: "semanticEmom",
  amrap: "semanticAmrap",
  for_time: "semanticForTime",
  tabata: "semanticTabata",
  fixed_duration: "semanticFixedDuration",
  rest: "semanticRest",
  untimed: "semanticUntimed",
  edt: "semanticEdt",
  death_by: "semanticDeathBy",
  custom_hiit: "semanticCustomHiit",
  ladder_ascending: "semanticAscendingLadder",
  ladder_descending: "semanticDescendingLadder",
  pyramid: "semanticPyramid",
  for_quality: "semanticForQuality",
  to_failure: "semanticToFailure",
  in_progress: "semanticInProgress",
  issued: "semanticIssued",
  partially_paid: "semanticPartiallyPaid",
  paid: "semanticPaid",
  void: "semanticVoid",
  scheduled: "semanticScheduled",
  no_recent_completion: "semanticNoRecentCompletion",
  overdue_assignment: "semanticOverdueAssignment",
  no_coaching_message: "semanticNoCoachingMessage",
  all: "semanticAll",
  admin_only: "semanticAdminOnly",
  user_visible: "semanticUserVisible",
  user_and_admin: "semanticUserAndAdmin",
  attention: "semanticAttention",
  drifting: "semanticDrifting",
  normal: "semanticNormal",
  urgent: "semanticUrgent",
  in_person: "semanticInPerson",
  events: "semanticEvents",
  facility: "semanticFacility",
  personal_training: "semanticPersonalTraining",
  digital_content: "semanticDigitalContent",
  nutrition: "semanticNutrition",
  waitlisted: "semanticWaitlisted",
  mixed: "semanticMixed",
  personal_programming: "semanticPersonalProgramming",
  annual: "semanticAnnual",
  quarterly: "semanticQuarterly",
  monthly: "semanticMonthly",
  calendar_week: "semanticCalendarWeek",
  calendar_month: "semanticCalendarMonth",
  subscription_period: "semanticSubscriptionPeriod",
  book_classes: "semanticBookClasses",
  class_visits: "semanticClassVisits",
  coach_messaging: "semanticCoachMessaging",
  coaching_touchpoints: "semanticCoachingTouchpoints",
  overview: "semanticOverview",
  finance: "semanticFinance",
  training_history: "semanticTrainingHistory",
  prs: "semanticPersonalRecords",
  scores: "semanticScores",
  health_incidents: "semanticHealthIncidents",
  class_participation: "semanticClassParticipation",
  messages: "semanticMessages",
  coaching_context: "semanticCoachingContext",
  admin_actions: "semanticAdminActions",
  receive_coaching_touchpoints: "semanticReceiveCoachingTouchpoints",
  execute_assigned_workouts: "semanticExecuteAssignedWorkouts",
  execute_class_workouts: "semanticExecuteClassWorkouts",
  execute_library_workouts: "semanticExecuteLibraryWorkouts",
  workout_library: "semanticWorkoutLibrary",
  applied: "semanticApplied",
  targeted: "semanticTargeted",
  pass: "semanticPass",
  fail: "semanticFail",
  unknown: "semanticUnknown",
  trial: "semanticTrial",
  expiring: "semanticExpiring",
  expired: "semanticExpired",
  comped: "semanticComped",
  waived: "semanticWaived",
  redeemed: "semanticRedeemed",
  available: "semanticAvailable",
  blocked: "semanticBlocked",
  fulfilled: "semanticFulfilled",
  grace: "semanticGrace",
  healed: "semanticHealed",
  failed: "semanticFailed",
  succeeded: "semanticSucceeded",
  error: "semanticError",
  loading: "semanticLoading",
  authenticated: "semanticAuthenticated",
  guest: "semanticGuest",
  unassigned: "semanticUnassigned",
  unmanaged: "semanticUnmanaged",
  no_active_package: "semanticNoActivePackage",
  open_invoice: "semanticOpenInvoice",
  overdue_invoice: "semanticOverdueInvoice",
  invoice_overdue: "semanticInvoiceOverdue",
  membership_expired: "semanticMembershipExpired",
  membership_paused: "semanticMembershipPaused",
};

const API_ERROR_KEYS: Record<string, string> = {
  // ADR-222: recording money received at the desk.
  payment_exceeds_invoice_balance: "apiErrorPaymentExceedsInvoiceBalance",
  invoice_already_paid: "apiErrorInvoiceAlreadyPaid",
  invoice_void: "apiErrorInvoiceVoid",
  payment_purpose_required: "apiErrorPaymentPurposeRequired",
  invalid_payment_amount: "apiErrorInvalidPaymentAmount",
  invalid_payment_method: "apiErrorInvalidPaymentMethod",
  // ADR-202: spaces, floor plans, the cleaning schedule and machine placement.
  space_unavailable: "apiErrorSpaceUnavailable",
  space_archived: "apiErrorSpaceArchived",
  space_wrong_branch: "apiErrorSpaceWrongBranch",
  space_not_found: "apiErrorSpaceNotFound",
  invalid_space_area: "apiErrorInvalidSpaceArea",
  invalid_unavailability: "apiErrorInvalidUnavailability",
  floor_plan_wrong_branch: "apiErrorFloorPlanWrongBranch",
  invalid_cleaning_schedule: "apiErrorInvalidCleaningSchedule",
  invalid_placement: "apiErrorInvalidPlacement",
  placement_exceeds_quantity: "apiErrorPlacementExceedsQuantity",
  // ADR-200: how far an edit to a class of a series goes.
  invalid_series_scope: "apiErrorInvalidSeriesScope",
  series_range_required: "apiErrorSeriesRangeRequired",
  invalid_series_every: "apiErrorInvalidSeriesEvery",
  invalid_class_action: "apiErrorInvalidClassAction",
  class_cancelled: "apiErrorClassCancelled",
  class_paused: "apiErrorClassPaused",
  class_has_bookings: "apiErrorClassHasBookings",
  // ADR-184: business accounts, demo mode and activation.
  business_not_activated: "apiErrorBusinessNotActivated",
  business_account_exists: "apiErrorBusinessAccountExists",
  business_signup_closed: "apiErrorBusinessSignupClosed",
  invalid_business_kind: "apiErrorInvalidBusinessKind",
  invalid_business_request: "apiErrorInvalidBusinessRequest",
  business_request_pending: "apiErrorBusinessRequestPending",
  business_request_closed: "apiErrorBusinessRequestClosed",
  invalid_activation_link: "apiErrorInvalidActivationLink",
  business_already_active: "apiErrorBusinessAlreadyActive",
  invalid_activation_role: "apiErrorInvalidActivationRole",
  invalid_activation_lifetime: "apiErrorInvalidActivationLifetime",
  account_not_found: "apiErrorAccountNotFound",
  unknown_demo_section: "apiErrorUnknownDemoSection",
  // ADR-170: platform plans and the solo-coach tier.
  coach_practice_exists: "apiErrorCoachPracticeExists",
  plan_limit_reached: "apiErrorPlanLimitReached",
  unknown_plan: "apiErrorUnknownPlan",
  trial_end_required: "apiErrorTrialEndRequired",
  invalid_name: "apiErrorInvalidName",
  no_coaching_relationship: "apiErrorNoCoachingRelationship",
  box_message_outside_box_thread: "apiErrorBoxMessageOutsideBoxThread",
  channel_not_optional: "apiErrorChannelNotOptional",
  invalid_notify_level: "apiErrorInvalidNotifyLevel",
  cannot_post_in_channel: "apiErrorCannotPostInChannel",
  attachment_not_shareable: "apiErrorAttachmentNotShareable",
  check_in_not_open: "apiErrorCheckInNotOpen",
  check_in_closed: "apiErrorCheckInClosed",
  attendance_already_recorded: "apiErrorAttendanceAlreadyRecorded",
  attendance_requires_approved_booking: "apiErrorAttendanceRequiresApprovedBooking",
  invalid_admin_registration_code: "apiErrorInvalidAdminRegistrationCode",
  invalid_invitation: "apiErrorInvalidInvitation",
  invitation_email_mismatch: "apiErrorInvitationEmailMismatch",
  // ADR-209: an email-bound invitation needs a confirmed address or its emailed link.
  invitation_email_unverified: "apiErrorInvitationEmailUnverified",
  invitation_revoked: "apiErrorInvitationRevoked",
  invalid_current_password: "apiErrorInvalidCurrentPassword",
  invalid_credentials: "apiErrorInvalidCredentials",
  invalid_refresh_token: "apiErrorInvalidRefreshToken",
  invalid_token: "apiErrorInvalidToken",
  token_issuance_failed: "apiErrorAuthenticationUnavailable",
  registration_cleanup_failed: "apiErrorRegistrationIncomplete",
  auth_dependency_unavailable: "apiErrorAuthenticationUnavailable",
  rate_limiter_unavailable: "apiErrorRateLimiterUnavailable",
  not_found: "apiErrorNotFound",
  cannot_delete_self: "apiErrorCannotDeleteSelf",
  last_admin: "apiErrorLastAdmin",
  user_has_restricted_history: "apiErrorUserHasRestrictedHistory",
  class_type_replacement_required: "apiErrorClassTypeReplacementRequired",
  invalid_class_type_replacement: "apiErrorInvalidClassTypeReplacement",
  last_active_class_type: "apiErrorLastActiveClassType",
  class_type_archived: "apiErrorClassTypeArchived",
  class_type_not_found: "apiErrorClassTypeNotFound",
  bad_request: "apiErrorBadRequest",
  self_conversation: "apiErrorSelfConversation",
  invalid_message: "apiErrorInvalidMessage",
  invalid_avatar_upload: "apiErrorInvalidAvatarUpload",
  avatar_upload_missing: "apiErrorAvatarUploadMissing",
  avatar_upload_unverified: "apiErrorAvatarUploadUnverified",
  unsupported_avatar_type: "apiErrorUnsupportedAvatarType",
  avatar_upload_metadata_missing: "apiErrorAvatarUploadMetadataMissing",
  avatar_too_large: "apiErrorAvatarTooLarge",
  avatar_key_forbidden: "apiErrorAvatarKeyForbidden",
  avatar_storage_unavailable: "apiErrorAvatarStorageUnavailable",
  invalid_brand_logo_upload: "apiErrorInvalidBrandLogoUpload",
  brand_logo_upload_missing: "apiErrorBrandLogoUploadMissing",
  unsupported_brand_logo_type: "apiErrorUnsupportedBrandLogoType",
  brand_logo_too_large: "apiErrorBrandLogoTooLarge",
  brand_logo_key_forbidden: "apiErrorBrandLogoKeyForbidden",
  brand_logo_storage_unavailable: "apiErrorBrandLogoStorageUnavailable",
  invalid_execution_source: "apiErrorInvalidExecutionSource",
  stale_execution: "apiErrorStaleExecution",
  execution_source_forbidden: "apiErrorExecutionSourceForbidden",
  execution_source_mismatch: "apiErrorExecutionSourceMismatch",
  completion_processing_unavailable: "apiErrorCompletionUnavailable",
  invalid_training_log_source: "apiErrorInvalidTrainingLogSource",
  training_log_source_forbidden: "apiErrorTrainingLogSourceForbidden",
  training_log_source_not_started: "apiErrorTrainingLogSourceNotStarted",
  training_log_already_counted: "apiErrorTrainingLogAlreadyCounted",
  training_log_source_already_logged: "apiErrorTrainingLogSourceAlreadyLogged",
  training_log_entry_voided: "apiErrorTrainingLogEntryVoided",
  stale_training_log_entry: "apiErrorStaleTrainingLogEntry",
  finance_profile_missing: "apiErrorSelfFinanceProfileMissing",
  finance_entitlement_inactive: "apiErrorSelfFinanceEntitlementInactive",
  finance_entitlement_blocked: "apiErrorSelfFinanceEntitlementBlocked",
  finance_entitlement_plan_missing: "apiErrorSelfFinanceEntitlementPlanMissing",
  finance_channel_not_included: "apiErrorSelfFinanceChannelNotIncluded",
  finance_capability_not_included: "apiErrorSelfFinanceCapabilityNotIncluded",
  finance_allowance_not_included: "apiErrorSelfFinanceAllowanceNotIncluded",
  finance_allowance_exhausted: "apiErrorSelfFinanceAllowanceExhausted",
  class_placement_requires_member: "apiErrorClassPlacementRequiresMember",
  folder_not_found: "apiErrorFolderNotFound",
  folder_cycle: "apiErrorFolderCycle",
  invalid_workout_icon: "apiErrorInvalidWorkoutIcon",
  finance_class_type_not_included: "apiErrorSelfFinanceClassTypeNotIncluded",
  package_type_invariant_violated: "apiErrorPackageTypeInvariantViolated",
  entitlement_not_available: "apiErrorEntitlementNotAvailable",
  invalid_package_field: "apiErrorInvalidPackageField",
  unknown_package_field: "apiErrorInvalidPackageField",
  package_rule_violated: "apiErrorPackageRuleViolated",
  invalid_package_type: "apiErrorInvalidPackageType",
  package_type_not_available: "apiErrorPackageTypeNotAvailable",
  package_type_change_requires_copy: "apiErrorPackageTypeChangeRequiresCopy",
  package_already_used: "apiErrorPackageAlreadyUsed",
  package_new_members_only: "apiErrorPackageNewMembersOnly",
  package_not_renewable: "apiErrorPackageNotRenewable",
  // ADR-220: renewal choice and leaving the box.
  renewal_turned_off: "apiErrorRenewalTurnedOff",
  member_leaving: "apiErrorMemberLeaving",
  renewal_choice_not_allowed: "apiErrorRenewalChoiceNotAllowed",
  subscription_ended: "apiErrorSubscriptionEnded",
  not_leaving: "apiErrorNotLeaving",
  already_left: "apiErrorAlreadyLeft",
  left_by_staff: "apiErrorLeftByStaff",
  invalid_leaving_on: "apiErrorInvalidLeavingOn",
  invalid_athletes: "apiErrorInvalidAthletes",
  programming_not_in_package: "apiErrorProgrammingNotInPackage",
  class_variant_requires_single_member: "apiErrorClassVariantRequiresSingleMember",
  slot_not_booked_by_member: "apiErrorSlotNotBookedByMember",
  // ADR-201: a coach with scope own programming someone who is not their client.
  not_your_client: "rhErrNotYourClient",
  slot_not_found: "apiErrorSlotNotFound",
  workout_not_published: "apiErrorWorkoutNotPublished",
  unauthorized: "apiErrorUnauthorized",
  forbidden: "apiErrorForbidden",
  validation_failed: "apiErrorValidationFailed",
  offline: "apiErrorOffline",
  idempotency_key_conflict: "apiErrorIdempotencyKeyConflict",
  booking_not_pending: "apiErrorBookingNotPending",
  // ADR-097 member booking codes
  booking_window_closed: "mbErrBookingWindowClosed",
  finance_membership_frozen: "mbErrMembershipFrozen",
  finance_time_window_not_included: "mbErrOutsidePackageHours",
  finance_location_not_included: "mbErrLocationNotIncluded",
  slot_full: "mbErrSlotFull",
  slot_in_past: "mbErrSlotInPast",
  slot_not_full: "mbErrSlotNotFull",
  // ADR-176
  class_not_published: "apiErrorClassNotPublished",
  // ADR-230: day WODs.
  day_in_the_past: "apiErrorDayInThePast",
  no_day_workout: "apiErrorNoDayWorkout",
  day_class_started: "apiErrorDayClassStarted",
  invalid_time_zone: "apiErrorInvalidTimeZone",
  time_zone_required: "apiErrorTimeZoneRequired",
  already_booked: "mbErrAlreadyBooked",
  invalid_guest_name: "mbErrInvalidGuestName",
  guest_already_booked: "mbErrGuestAlreadyBooked",
  location_archived: "mbErrLocationArchived",
  // ADR-186 branch scope
  location_out_of_scope: "apiErrorLocationOutOfScope",
  location_required: "apiErrorLocationRequired",
  location_scope_exceeded: "apiErrorLocationScopeExceeded",
  invalid_location_scope: "apiErrorInvalidLocationScope",
  owner_location_scope: "apiErrorOwnerLocationScope",
  cannot_change_own_membership: "apiErrorCannotChangeOwnMembership",
  role_ceiling_exceeded: "apiErrorRoleCeilingExceeded",
  own_top_role_locked: "apiErrorOwnTopRoleLocked",
  promotion_location_not_included: "apiErrorPromotionLocationNotIncluded",
  location_not_found: "mbErrLocationNotFound",
  // ADR-097 admin codes
  invalid_freeze_dates: "admErrInvalidFreezeDates",
  freeze_in_past: "admErrFreezeInPast",
  freeze_not_included: "admErrFreezeNotIncluded",
  freeze_overlaps: "admErrFreezeOverlaps",
  freeze_allowance_exceeded: "admErrFreezeAllowanceExceeded",
  freeze_already_cancelled: "admErrFreezeAlreadyCancelled",
  package_commitment_active: "admErrPackageCommitmentActive",
};

const ADMIN_ASSIGNMENT_ERROR_KEYS: Record<string, string> = {
  finance_profile_missing: "apiErrorFinanceProfileMissing",
  finance_entitlement_inactive: "apiErrorFinanceEntitlementInactive",
  finance_entitlement_blocked: "apiErrorFinanceEntitlementBlocked",
  finance_entitlement_plan_missing: "apiErrorFinanceEntitlementPlanMissing",
  finance_channel_not_included: "apiErrorFinanceChannelNotIncluded",
  finance_capability_not_included: "apiErrorFinanceCapabilityNotIncluded",
  finance_allowance_not_included: "apiErrorFinanceAllowanceNotIncluded",
  finance_allowance_exhausted: "apiErrorFinanceAllowanceExhausted",
  finance_class_type_not_included: "apiErrorFinanceClassTypeNotIncluded",
};

const WORKOUT_PROBLEMS = new Set(["no_content", "incomplete_sections", "invalid_details"]);

const PACKAGE_RULES = new Set([
  "validity_required",
  "limited_quota_required",
  "positive_quota_required",
  "at_least_one_service",
  "coaching_channel_required",
  "class_type_limit_outside_scope",
  "conversion_only_for_trials",
]);

const CLASS_TYPE_ALLOWANCE_PREFIX = "class_visits:";

// ADR-097 member allowance labels
const MEMBER_ALLOWANCE_KEYS: Record<string, string> = {
  event_visits: "mbAllowanceEventVisits",
  guest_passes: "mbAllowanceGuestPasses",
  open_gym_visits: "mbAllowanceOpenGymVisits",
  // ADR-098
  pt_sessions: "mbAllowancePtSessions",
  assessments: "mbAllowanceAssessments",
  form_reviews: "mbAllowanceFormReviews",
};

/** Label for an allowance key, including per-class-type allowances (ADR-096). */
export function allowanceLabel(
  key: string,
  translate: UiTranslator,
  classTypeNames?: Record<string, string> | null,
): string {
  if (key.startsWith(CLASS_TYPE_ALLOWANCE_PREFIX)) {
    const id = key.slice(CLASS_TYPE_ALLOWANCE_PREFIX.length);
    return translate("pkgAllowanceClassTypeVisits", {
      name: classTypeNames?.[id] ?? translate("pkgUnknownClassType"),
    });
  }
  const memberKey = MEMBER_ALLOWANCE_KEYS[key];
  if (memberKey) return translate(memberKey);
  return semanticLabel(key, translate);
}

// Staff and client roles read as a word for the person, never the department,
// and a member always says what of (docs/product/ontology.md §4.3).
const ROLE_KEYS: Record<string, string> = {
  owner: "roleOwner",
  admin: "roleAdmin",
  coach: "roleCoach",
  // A coach with `coach_scope: all` (ontology §4.3).
  head_coach: "roleHeadCoach",
  front_desk: "roleFrontDesk",
  accountant: "roleAccountant",
  janitor: "roleJanitor",
  member: "roleMember",
  athlete: "roleAthlete",
};

export function roleLabel(value: unknown, translate: UiTranslator): string {
  const key = ROLE_KEYS[String(value ?? "").toLowerCase()];
  return key ? translate(key) : semanticLabel(value, translate);
}

export function semanticLabel(value: unknown, translate: UiTranslator): string {
  if (value == null || value === "") return "";
  const canonical = String(value).toLowerCase();
  const key = SEMANTIC_KEYS[canonical];
  return key ? translate(key) : canonical.replaceAll("_", " ");
}

export function localizeError(error: unknown, translate: UiTranslator): string {
  if (!(error instanceof ApiError)) return translate("apiErrorRequestFailed");

  // ADR-214: a form that does not mark its fields still says, in plain
  // words, what was not accepted, never "check the highlighted values".
  if (error.status === 422 && (!error.payload.code || error.payload.code === "validation_failed")) {
    const details = new Set(
      Object.values(fieldMessagesOf(error.payload.errors)).map((messages) => explainFieldMessage(messages[0], translate)),
    );
    if (details.size > 0) return translate("apiErrorValidationFailedDetail", { details: [...details].join(" ") });
  }

  const rule = error.payload.params?.rule;
  if (error.payload.code === "package_rule_violated" && typeof rule === "string" && PACKAGE_RULES.has(rule)) {
    return translate(`apiErrorPackageRule_${rule}`);
  }

  // A WOD that cannot be given to anyone: name it and what it lacks.
  const problem = error.payload.params?.problem;
  if (error.payload.code === "workout_not_assignable" && typeof problem === "string" && WORKOUT_PROBLEMS.has(problem)) {
    const title = error.payload.params?.title;
    return translate(`apiErrorWorkoutNotAssignable_${problem}`, { title: typeof title === "string" && title ? title : "WOD" });
  }

  const key = error.payload.code ? API_ERROR_KEYS[error.payload.code] : undefined;
  if (key) {
    return translate(key, normalizeParams(error.payload.params, translate));
  }

  if (error.status === 401) return translate("apiErrorUnauthorized");
  if (error.status === 403) return translate("apiErrorForbidden");
  if (error.status === 404) return translate("apiErrorNotFound");
  if (error.status === 409) return translate("apiErrorConflict");
  if (error.status === 422) return translate("apiErrorValidationFailed");
  if (error.status === 429) return translate("apiErrorRateLimited");
  if (error.status >= 500) return translate("apiErrorServiceUnavailable");
  return translate("apiErrorRequestFailed");
}

export function localizeAdminAssignmentError(
  error: unknown,
  translate: UiTranslator,
): string {
  if (error instanceof ApiError && error.payload.code) {
    const key = ADMIN_ASSIGNMENT_ERROR_KEYS[error.payload.code];
    if (key) return translate(key, normalizeParams(error.payload.params, translate));
  }

  return localizeError(error, translate);
}

export function formatScore(
  value: unknown,
  scoreType: unknown,
  unit: unknown,
  translate: UiTranslator,
): string {
  const text = value == null ? "" : String(value);

  if (scoreType === "rounds+reps" || scoreType === "rounds_reps") {
    const both = text.match(/^(\d+) rounds \+ (\d+) reps$/i);
    if (both) return translate("scoreRoundsAndReps", { rounds: Number(both[1]), reps: Number(both[2]) });
    const rounds = text.match(/^(\d+) rounds?$/i);
    if (rounds) return translate("scoreRoundsOnly", { rounds: Number(rounds[1]) });
    const reps = text.match(/^(\d+) reps?$/i);
    if (reps) return translate("scoreRepsOnly", { reps: Number(reps[1]) });
  }

  if (scoreType === "pass_fail") return semanticLabel(text, translate);
  // ADR-180: section results store time as seconds.
  if (scoreType === "time" && unit === "s" && typeof value === "number" && value >= 0) return clockFromSeconds(value);
  const localizedUnit = semanticLabel(unit, translate);
  return localizedUnit ? `${text} ${localizedUnit}` : text;
}

function clockFromSeconds(total: number) {
  const seconds = Math.round(total);
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = String(seconds % 60).padStart(2, "0");
  return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${s}` : `${m}:${s}`;
}

function normalizeParams(params: Record<string, unknown> | undefined, translate: UiTranslator) {
  if (!params) return undefined;
  const allowance = params.allowance;
  if (typeof allowance === "string" && allowance.startsWith(CLASS_TYPE_ALLOWANCE_PREFIX)) {
    params = { ...params, allowance: translate("pkgAllowanceClassTypeVisits", { name: translate("pkgUnknownClassType") }) };
  }
  return Object.fromEntries(
    Object.entries(params)
      .filter(
        (entry): entry is [string, string | number] =>
          typeof entry[1] === "string" || typeof entry[1] === "number",
      )
      .map(([key, value]) => [
        key,
        typeof value === "string" && ["channel", "capability", "allowance"].includes(key)
          ? value.replaceAll("_", " ")
          : value,
      ]),
  );
}

/** One plain-language sentence for a validation message of the API (Ecto wording). */
export function explainFieldMessage(rawMessage: string, translate: UiTranslator): string {
  const message = rawMessage.trim();
  const number = (pattern: RegExp) => message.match(pattern)?.[1];

  if (message === "can't be blank" || message === "is required") return translate("formErrRequired");
  if (message === "must be in the future") return translate("formErrMustBeFuture");
  if (message === "has already been taken") return translate("formErrTaken");
  if (message === "does not exist") return translate("formErrNotFound");
  if (message === "must be accepted") return translate("formErrMustAccept");

  let value: string | undefined;
  if ((value = number(/^must be greater than or equal to (-?[\d.]+)$/))) return translate("formErrAtLeast", { number: value });
  if ((value = number(/^must be greater than (-?[\d.]+)$/))) return translate("formErrGreaterThan", { number: value });
  if ((value = number(/^must be less than or equal to (-?[\d.]+)$/))) return translate("formErrAtMost", { number: value });
  if ((value = number(/^must be less than (-?[\d.]+)$/))) return translate("formErrLessThan", { number: value });
  if ((value = number(/^must be equal to (-?[\d.]+)$/))) return translate("formErrEqualTo", { number: value });
  if ((value = number(/^should be at most (\d+) character\(s\)$/))) return translate("formErrTooLong", { count: Number(value) });
  if ((value = number(/^should be at least (\d+) character\(s\)$/))) return translate("formErrTooShort", { count: Number(value) });
  if ((value = number(/^should be (\d+) character\(s\)$/))) return translate("formErrExactLength", { count: Number(value) });
  if ((value = number(/^should have at most (\d+) item\(s\)$/))) return translate("formErrTooManyItems", { count: Number(value) });
  if ((value = number(/^should have at least (\d+) item\(s\)$/))) return translate("formErrTooFewItems", { count: Number(value) });

  return translate("formErrInvalid");
}

/** `{field: ["msg", ...]}` for every field with at least one text message (nested maps flattened with dots). */
export function fieldMessagesOf(errors: unknown, prefix = ""): Record<string, string[]> {
  if (!errors || typeof errors !== "object" || Array.isArray(errors)) return {};

  const result: Record<string, string[]> = {};
  for (const [field, value] of Object.entries(errors as Record<string, unknown>)) {
    const key = prefix ? `${prefix}.${field}` : field;
    if (typeof value === "string") {
      result[key] = [value];
    } else if (Array.isArray(value)) {
      const texts = value.filter((item): item is string => typeof item === "string");
      if (texts.length > 0) result[key] = texts;
      value.forEach((item, index) => {
        if (item && typeof item === "object") Object.assign(result, fieldMessagesOf(item, `${key}.${index}`));
      });
    } else if (value && typeof value === "object") {
      Object.assign(result, fieldMessagesOf(value, key));
    }
  }
  return result;
}
