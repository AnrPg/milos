defmodule PaleeWeb.RouteCapabilities do
  @moduledoc """
  The capability each staff route needs (ADR-099). A request passes when the
  tenant context holds ANY of the listed capabilities; data scope (a coach's
  own clients, ADR-100) is enforced by the application services behind it.

  Every `/api/org/:slug/admin` and `/api/org/:slug/staff` route must be listed:
  `RouteCapabilitiesTest` fails on a route without an entry, so a new staff
  endpoint can never fall back to "any staff member".
  """

  alias PaleeWeb, as: W

  @controller_defaults %{
    W.AdminWorkoutController => [:manage_workouts],
    W.AdminWorkoutDslController => [:manage_workouts],
    W.AdminWorkoutFolderController => [:manage_workouts],
    W.AdminWorkoutGoalsController => [:manage_workouts],
    W.AdminChallengeController => [:manage_challenges],
    W.AdminAssignedWorkoutController => [:manage_coaching],
    W.AdminContentController => [:manage_content],
    W.AdminCoachingController => [:view_client_training],
    W.AdminReviewController => [:view_feedback],
    W.AdminWellbeingController => [:view_health],
    W.AdminInjuryWarningController => [:view_health],
    W.AdminSearchController => [:view_directory],
    W.AdminAnalyticsController => [:view_business_analytics],
    W.CoachingExtrasController => [:manage_coaching],
    W.AppointmentsController => [:manage_appointments],
    W.StaffController => [:manage_coaching, :manage_appointments, :manage_schedule],
    W.PaymentModelsController => [:manage_billing],
    W.CoachingRelationshipsController => [:assign_coaches, :manage_coaching],
    W.RoleAccessController => [:manage_settings],
    W.InventoryController => [:manage_inventory],
    W.OwnerOrganizationController => [:manage_organization_lifecycle],
    W.AdminWorkoutTimerPreviewController => [:manage_workouts],
    W.AdminBrandingController => [:manage_settings],
    W.AdminPublicProfileController => [:manage_settings],
    W.HomeLocationController => [:manage_memberships],
    W.AdminWorkoutFreeTextController => [:manage_workouts],
    W.AdminOnboardingController => [:manage_settings],
    # ADR-170: the platform plan card (owners and admins hold manage_settings).
    W.AdminPlanController => [:manage_settings],
    W.TrainingHistoryController => [:view_client_training],
    # ADR-174: the queue also requires view_health per athlete (service).
    W.StaffScalingController => [:manage_coaching],
    W.AdminAiSettingsController => [:manage_settings]
  }

  @actions %{
    # People
    {W.AdminUserController, :index} => [:view_directory, :view_billing_contacts],
    {W.AdminUserController, :index_athletes} => [:view_directory],
    {W.AdminUserController, :show} => [:view_directory, :view_billing_contacts],
    {W.AdminUserController, :finance} => [:manage_billing, :take_payments],
    {W.AdminUserController, :training_history} => [:view_client_training],
    {W.AdminUserController, :schedule} => [:view_client_training, :run_classes],
    {W.AdminUserController, :program_workout} => [:manage_coaching],
    {W.AdminUserController, :place_in_class} => [:book_for_clients, :manage_schedule],
    {W.AdminUserController, :prs} => [:view_client_training],
    {W.AdminUserController, :pr_members} => [:view_client_training],
    {W.AdminUserController, :incidents} => [:view_health],
    {W.AdminUserController, :messages} => [:message_clients],
    {W.AdminUserController, :coaching_context} => [:view_client_training],
    {W.AdminUserController, :grant_allowance} => [:manage_billing],
    {W.AdminUserController, :revoke_allowance} => [:manage_billing],
    {W.AdminUserController, :freezes} => [:manage_billing, :take_payments],
    {W.AdminUserController, :create_freeze} => [:manage_billing],
    {W.AdminUserController, :cancel_freeze} => [:manage_billing],
    {W.AdminUserController, :delete} => [:manage_memberships],
    {W.AdminUserController, :update_role} => [:grant_staff_roles],
    {W.AdminUserController, :update_roles} => [:grant_staff_roles],
    {W.AdminUserController, :update_coach_scope} => [:set_head_coach],
    {W.AdminUserController, :membership_status} => [:view_membership_status],

    # Gym settings and facility
    {W.AdminSettingsController, :show} => [:manage_settings, :manage_finance_settings],
    {W.AdminSettingsController, :update} => [:manage_settings],
    {W.AdminFacilityController, :index_locations} => [
      :manage_settings,
      :manage_schedule,
      :check_in,
      :review_cleaning
    ],
    {W.AdminFacilityController, :create_location} => [:manage_settings],
    {W.AdminFacilityController, :update_location} => [:manage_settings],
    {W.AdminFacilityController, :archive_location} => [:manage_settings],
    {W.AdminFacilityController, :search_addresses} => [:manage_settings],
    {W.AdminFacilityController, :reverse_geocode} => [:manage_settings],
    {W.AdminFacilityController, :resolve_map_link} => [:manage_settings],
    {W.AdminFacilityController, :index_check_ins} => [:check_in],
    {W.AdminFacilityController, :create_check_in} => [:check_in],
    # ADR-155: QR check-in desk, door display and rules.
    {W.AdminCheckInController, :door} => [:check_in],
    {W.AdminCheckInController, :rotate_door} => [:check_in, :manage_settings],
    {W.AdminCheckInController, :poster} => [:check_in, :manage_settings],
    {W.AdminCheckInController, :update_poster} => [:manage_settings],
    {W.AdminCheckInController, :rotate_poster} => [:manage_settings],
    {W.AdminCheckInController, :nfc_tag} => [:check_in, :manage_settings],
    {W.AdminCheckInController, :update_nfc_tag} => [:manage_settings],
    {W.AdminCheckInController, :rotate_nfc_tag} => [:manage_settings],
    {W.AdminCheckInController, :revoke_member_code} => [:check_in],
    {W.AdminCheckInController, :scan_member} => [:check_in],
    {W.AdminCheckInController, :check_in_member} => [:check_in],
    {W.AdminCheckInController, :visitors} => [:check_in],
    {W.AdminCheckInController, :settings} => [:manage_settings, :check_in],
    {W.AdminCheckInController, :update_settings} => [:manage_settings],
    {W.AdminClassTypeController, :index} => [:manage_schedule, :run_classes, :manage_workouts],
    {W.AdminClassTypeController, :create} => [:manage_settings],
    {W.AdminClassTypeController, :update} => [:manage_settings],
    {W.AdminClassTypeController, :delete} => [:manage_settings],
    {W.AdminScaleLevelController, :index} => [:manage_workouts, :manage_settings],
    {W.AdminScaleLevelController, :update} => [:manage_settings],

    # Trials (ADR-144)
    {W.AdminTrialController, :policy} => [:manage_settings],
    {W.AdminTrialController, :update_policy} => [:manage_settings],
    {W.AdminTrialController, :queue} => [:run_classes, :manage_memberships, :manage_settings],
    {W.AdminTrialController, :accept} => [:run_classes, :manage_memberships],
    {W.AdminTrialController, :decline} => [:run_classes, :manage_memberships],
    {W.AdminTrialController, :attendance} => [:run_classes],

    # «Κοινότητα» (ADR-143)
    {W.AdminCommunityController, :groups} => [:moderate_community],
    {W.AdminCommunityController, :decide_group} => [:moderate_community],
    {W.AdminCommunityController, :reopen_group} => [:moderate_community],
    {W.AdminCommunityController, :update_settings} => [:manage_community],
    {W.AdminCommunityController, :reports} => [:moderate_community],
    {W.AdminCommunityController, :act_on_report} => [:moderate_community],
    {W.AdminCommunityController, :clubs} => [:moderate_community],
    {W.AdminCommunityController, :create_club} => [:manage_community],
    {W.AdminCommunityController, :club} => [:moderate_community],
    {W.AdminCommunityController, :update_club} => [:manage_community],
    {W.AdminCommunityController, :archive_club} => [:manage_community],
    {W.AdminCommunityController, :answer_club_request} => [:moderate_community],
    {W.AdminCommunityController, :remove_club_member} => [:moderate_community],

    # Club events (ADR-153): the desk works the door of an event.
    {W.AdminCommunityEventController, :index} => [:manage_events, :check_in, :take_payments],
    {W.AdminCommunityEventController, :show} => [:manage_events, :check_in, :take_payments],
    {W.AdminCommunityEventController, :create} => [:manage_events],
    {W.AdminCommunityEventController, :update} => [:manage_events],
    {W.AdminCommunityEventController, :cancel} => [:manage_events],
    {W.AdminCommunityEventController, :check_in} => [:manage_events, :check_in],
    {W.AdminCommunityEventController, :mark_paid} => [:manage_events, :take_payments],
    {W.AdminCommunityEventController, :remove} => [:manage_events],
    {W.AdminCommunityEventController, :message} => [:manage_events],
    {W.AdminCommunityEventController, :trial_offer} => [:manage_events],

    # Schedule
    {W.AdminScheduleController, :create_slot} => [:manage_schedule],
    {W.AdminScheduleController, :create_series} => [:manage_schedule],
    {W.AdminScheduleController, :update_slot} => [:manage_schedule],
    {W.AdminScheduleController, :delete_slot} => [:manage_schedule],
    {W.AdminScheduleController, :approve_booking} => [:run_classes],
    {W.AdminScheduleController, :reject_booking} => [:run_classes],
    {W.AdminScheduleController, :record_attendance} => [:run_classes],
    # ADR-163: coach totals of a class's «τι ένιωσες»; row security decides
    # which entries count (a coach of the gym, the entry's rung).
    {W.AdminWorkoutGoalsController, :class_feedback_summary} => [:manage_workouts, :run_classes],

    # Finance
    {W.AdminFinanceAccountingController, :refund_receipts} => [
      :manage_billing,
      :take_payments,
      :view_finance_reports
    ],
    {W.AdminFinanceAccountingController, :refund_receipt} => [
      :manage_billing,
      :take_payments,
      :view_finance_reports
    ],
    {W.AdminFinanceAccountingController, :refund_receipt_document} => [
      :manage_billing,
      :take_payments,
      :view_finance_reports
    ],
    {W.AdminFinanceAccountingController, :reconciliation_records} => [
      :manage_billing,
      :view_finance_reports
    ],
    {W.AdminFinanceAccountingController, :reconciliation_candidates} => [:manage_billing],
    {W.AdminFinanceAccountingController, :record_reconciliation_line} => [:manage_billing],
    {W.AdminFinanceAccountingController, :match_reconciliation} => [:manage_billing],
    {W.AdminFinanceAccountingController, :unmatch_reconciliation} => [:manage_billing],
    {W.AdminFinanceAccountingController, :exports} => [:manage_billing, :view_finance_reports],
    {W.AdminFinanceAccountingController, :request_export} => [
      :manage_billing,
      :view_finance_reports
    ],
    {W.AdminFinanceAccountingController, :export_download} => [
      :manage_billing,
      :view_finance_reports
    ],
    {W.AdminFinanceController, :summary} => [:view_finance_reports],
    {W.AdminFinanceController, :operational_queues} => [:view_finance_reports],
    {W.AdminFinanceController, :cleanup_records} => [:manage_billing],
    {W.AdminFinanceController, :purge_record} => [:manage_billing],
    {W.AdminFinanceController, :packages} => [:view_package_catalog],
    # ADR-167: seasons are sold like packages; places are answered like payments.
    {W.AdminSeasonController, :index} => [:view_package_catalog, :take_payments],
    {W.AdminSeasonController, :show} => [:view_package_catalog, :take_payments],
    {W.AdminSeasonController, :create} => [:manage_packages],
    {W.AdminSeasonController, :update} => [:manage_packages],
    {W.AdminSeasonController, :confirm} => [:take_payments, :manage_memberships],
    {W.AdminSeasonController, :decline} => [:take_payments, :manage_memberships],
    {W.AdminSeasonController, :remove} => [:take_payments, :manage_memberships],
    {W.AdminFinanceController, :package_catalog} => [:view_package_catalog],
    {W.AdminFinanceController, :package} => [:view_package_catalog],
    {W.AdminFinanceController, :create_package} => [:manage_packages],
    {W.AdminFinanceController, :update_package} => [:manage_packages],
    {W.AdminFinanceController, :retire_package} => [:manage_packages],
    {W.AdminFinanceController, :backfill_entitlements} => [:manage_billing],
    {W.AdminFinanceController, :members} => [:manage_billing, :take_payments],
    {W.AdminFinanceController, :member} => [:manage_billing, :take_payments],
    {W.AdminFinanceController, :update_member} => [:manage_billing],
    {W.AdminFinanceController, :assign_package} => [:take_payments],
    {W.AdminFinanceController, :record_payment} => [:take_payments],
    {W.AdminFinanceController, :create_receipt} => [:take_payments],
    {W.AdminFinanceController, :redeem_promotion} => [:take_payments],
    {W.AdminFinanceController, :create_invoice} => [:manage_billing],
    {W.AdminFinanceController, :generate_renewal_invoice} => [:manage_billing],
    {W.AdminFinanceController, :create_manual_credit} => [:manage_billing],
    {W.AdminFinanceController, :apply_credit_to_payment} => [:manage_billing],
    {W.AdminFinanceController, :reverse_payment} => [:manage_billing],
    {W.AdminFinanceController, :apply_credit_to_invoice} => [:manage_billing],
    {W.AdminFinanceController, :reverse_credit_ledger_entry} => [:manage_billing],
    {W.AdminFinanceController, :update_invoice} => [:manage_billing],
    {W.AdminFinanceController, :issue_invoice} => [:manage_billing],
    {W.AdminFinanceController, :void_invoice} => [:manage_billing],
    {W.AdminFinanceController, :invoice_upload_url} => [:manage_billing],
    {W.AdminFinanceController, :invoice_upload_complete} => [:manage_billing],
    {W.AdminFinanceController, :invoice_download_url} => [:manage_billing],
    {W.AdminFinanceController, :promotions} => [:manage_promotions, :view_promotions],
    {W.AdminFinanceController, :create_promotion} => [:manage_promotions],
    {W.AdminFinanceController, :promotion_codes} => [:manage_promotions, :view_promotions],
    {W.AdminFinanceController, :create_promotion_code} => [:manage_promotions],
    {W.AdminFinanceController, :referral_programs} => [:manage_promotions, :view_promotions],
    {W.AdminFinanceController, :create_referral_program} => [:manage_promotions],
    {W.AdminFinanceController, :update_referral_program} => [:manage_promotions],
    {W.AdminFinanceController, :referrals} => [:manage_promotions, :view_promotions],
    {W.AdminFinanceController, :create_referral} => [:manage_promotions],
    {W.AdminFinanceController, :update_referral_status} => [:manage_promotions],
    {W.AdminFinanceController, :referral_rewards} => [:manage_promotions, :view_promotions],
    {W.AdminFinanceController, :create_referral_reward} => [:manage_promotions],
    {W.AdminFinanceController, :update_referral_reward_status} => [:manage_promotions],
    # ADR-156: invites.
    {W.AdminReferralController, :index} => [:manage_promotions, :view_promotions],
    {W.AdminReferralController, :approve} => [:manage_promotions],
    {W.AdminReferralController, :reject} => [:manage_promotions],
    {W.AdminReferralController, :given} => [:manage_promotions],
    {W.AdminReferralController, :reassign} => [:manage_promotions],
    {W.AdminReferralController, :friend_gift} => [:manage_promotions],

    # Staff appointments: front desk books and cancels for clients.
    {W.AppointmentsController, :slots} => [:manage_appointments, :book_for_clients],
    {W.AppointmentsController, :book_for_client} => [:manage_appointments, :book_for_clients],
    {W.AppointmentsController, :cancel} => [:manage_appointments, :book_for_clients],

    # A client's journal through the coach seam (ADR-139 §6)
    {W.JournalController, :client_journal} => [:manage_coaching],
    # ADR-158: health data; the use case also requires the coach role.
    {W.ClientBodyController, :index} => [:view_health],
    {W.ClientBodyController, :show} => [:view_health],
    {W.ClientBodyController, :series} => [:view_health],
    # ADR-160: the weekly wellness summary; the use case also requires the
    # coach role and the client's grant.
    {W.ClientWellnessSummaryController, :show} => [:view_health],
    # ADR-165: coverage, qualities and load from shared entries; the use
    # case also requires the coach role and the client in scope.
    {W.TrainingDepthController, :client} => [:view_client_training],

    # Private coach notes (ADR-101)
    {W.CoachNotesController, :index} => [:write_coach_notes, :read_coach_notes],
    {W.CoachNotesController, :create} => [:write_coach_notes],
    {W.CoachNotesController, :update} => [:write_coach_notes],
    {W.CoachNotesController, :delete} => [:write_coach_notes],
    {W.CoachNotesController, :reads} => [:write_coach_notes],
    {W.CoachNotesController, :visibility} => [:write_coach_notes],

    # Cleaning log (ADR-102)
    {W.CleaningController, :areas} => [:record_cleaning, :review_cleaning, :manage_cleaning_areas],
    {W.CleaningController, :create_area} => [:manage_cleaning_areas],
    {W.CleaningController, :update_area} => [:manage_cleaning_areas],
    {W.CleaningController, :archive_area} => [:manage_cleaning_areas],
    {W.CleaningController, :entries} => [:record_cleaning, :review_cleaning],
    {W.CleaningController, :start} => [:record_cleaning],
    {W.CleaningController, :finish} => [:record_cleaning],

    # Invitations
    {W.OrganizationAccessController, :issue} => [:invite_clients],
    {W.OrganizationAccessController, :list_invitations} => [:invite_clients],
    {W.OrganizationAccessController, :show_join_link} => [:invite_clients],
    {W.OrganizationAccessController, :update_join_link} => [:invite_clients],
    {W.OrganizationAccessController, :revoke} => [:invite_clients],
    # ADR-104: the whole team reports; front desk, admins and owners manage.
    {W.InventoryController, :machines} => [:manage_inventory, :report_inventory],
    {W.InventoryController, :machine_events} => [:manage_inventory, :report_inventory],
    {W.InventoryController, :log_machine_event} => [:manage_inventory, :report_inventory],
    {W.InventoryController, :supplies} => [:manage_inventory, :report_inventory],
    {W.InventoryController, :report_low} => [:manage_inventory, :report_inventory],
    {W.InventoryController, :supply_reports} => [:manage_inventory, :report_inventory]
  }

  @doc "Capabilities that each grant the route, or nil when unlisted."
  def for_action(controller, action) do
    Map.get(@actions, {controller, action}) || Map.get(@controller_defaults, controller)
  end
end
