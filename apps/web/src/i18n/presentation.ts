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
  coaching_note: "semanticCoachingNote",
  system: "semanticSystem",
  workout_count: "semanticWorkoutCount",
  workout_type_count: "semanticWorkoutTypeCount",
  pr_count: "semanticPrCount",
  custom: "semanticCustom",
  unlimited: "semanticUnlimited",
  "limited-visits": "semanticLimitedVisits",
  hybrid: "semanticHybrid",
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
  no_admin_note: "semanticNoAdminNote",
  all: "semanticAll",
  admin_only: "semanticAdminOnly",
  user_visible: "semanticUserVisible",
  user_and_admin: "semanticUserAndAdmin",
  attention: "semanticAttention",
  drifting: "semanticDrifting",
  normal: "semanticNormal",
  urgent: "semanticUrgent",
  in_person: "semanticInPerson",
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
  invalid_admin_registration_code: "apiErrorInvalidAdminRegistrationCode",
  invalid_current_password: "apiErrorInvalidCurrentPassword",
  invalid_credentials: "apiErrorInvalidCredentials",
  invalid_refresh_token: "apiErrorInvalidRefreshToken",
  invalid_token: "apiErrorInvalidToken",
  token_issuance_failed: "apiErrorAuthenticationUnavailable",
  registration_cleanup_failed: "apiErrorRegistrationIncomplete",
  auth_dependency_unavailable: "apiErrorAuthenticationUnavailable",
  rate_limiter_unavailable: "apiErrorRateLimiterUnavailable",
  not_found: "apiErrorNotFound",
  class_type_replacement_required: "apiErrorClassTypeReplacementRequired",
  invalid_class_type_replacement: "apiErrorInvalidClassTypeReplacement",
  last_active_class_type: "apiErrorLastActiveClassType",
  class_type_archived: "apiErrorClassTypeArchived",
  class_type_not_found: "apiErrorClassTypeNotFound",
  bad_request: "apiErrorBadRequest",
  self_conversation: "apiErrorSelfConversation",
  invalid_message: "apiErrorInvalidMessage",
  invalid_avatar_upload: "apiErrorInvalidAvatarUpload",
  invalid_execution_source: "apiErrorInvalidExecutionSource",
  stale_execution: "apiErrorStaleExecution",
  execution_source_forbidden: "apiErrorExecutionSourceForbidden",
  execution_source_mismatch: "apiErrorExecutionSourceMismatch",
  completion_processing_unavailable: "apiErrorCompletionUnavailable",
  unauthorized: "apiErrorUnauthorized",
  forbidden: "apiErrorForbidden",
  validation_failed: "apiErrorValidationFailed",
  offline: "apiErrorOffline",
};

export function semanticLabel(value: unknown, translate: UiTranslator): string {
  if (value == null || value === "") return "";
  const canonical = String(value).toLowerCase();
  const key = SEMANTIC_KEYS[canonical];
  return key ? translate(key) : canonical.replaceAll("_", " ");
}

export function localizeError(error: unknown, translate: UiTranslator): string {
  if (!(error instanceof ApiError)) return translate("apiErrorRequestFailed");

  const key = error.payload.code ? API_ERROR_KEYS[error.payload.code] : undefined;
  if (key) {
    return translate(key, normalizeParams(error.payload.params));
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
  const localizedUnit = semanticLabel(unit, translate);
  return localizedUnit ? `${text} ${localizedUnit}` : text;
}

function normalizeParams(params: Record<string, unknown> | undefined) {
  if (!params) return undefined;
  return Object.fromEntries(
    Object.entries(params).filter(
      (entry): entry is [string, string | number] =>
        typeof entry[1] === "string" || typeof entry[1] === "number",
    ),
  );
}
