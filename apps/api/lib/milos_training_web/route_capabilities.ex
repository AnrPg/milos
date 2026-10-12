defmodule MilosTrainingWeb.RouteCapabilities do
  @moduledoc """
  The capability each staff route needs (ADR-099). A request passes when the
  tenant context holds ANY of the listed capabilities; data scope (a coach's
  own clients, ADR-100) is enforced by the application services behind it.

  Every `/api/org/:slug/admin` and `/api/org/:slug/staff` route must be listed:
  `RouteCapabilitiesTest` fails on a route without an entry, so a new staff
  endpoint can never fall back to "any staff member".
  """

  alias MilosTrainingWeb, as: W

  @controller_defaults %{
    W.AdminWorkoutController => [:manage_workouts],
    W.AdminWorkoutDslController => [:manage_workouts],
    W.AdminWorkoutFolderController => [:manage_workouts],
    W.AdminChallengeController => [:manage_challenges],
    W.AdminAssignedWorkoutController => [:manage_coaching],
    W.AdminContentController => [:manage_content],
    W.AdminCoachingController => [:view_client_training],
    W.AdminReviewController => [:view_feedback],
    W.AdminWellbeingController => [:view_health],
    W.AdminSearchController => [:view_directory],
    W.AdminAnalyticsController => [:view_business_analytics],
    W.CoachingExtrasController => [:manage_coaching],
    W.AppointmentsController => [:manage_appointments],
    W.StaffController => [:manage_coaching, :manage_appointments, :manage_schedule],
    W.PaymentModelsController => [:manage_billing],
    W.CoachingRelationshipsController => [:assign_coaches, :manage_coaching],
    W.RoleAccessController => [:manage_settings],
    W.OwnerOrganizationController => [:manage_organization_lifecycle]
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
    {W.AdminUserController, :prs} => [:view_client_training],
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
    {W.AdminFacilityController, :index_check_ins} => [:check_in],
    {W.AdminFacilityController, :create_check_in} => [:check_in],
    {W.AdminClassTypeController, :index} => [:manage_schedule, :run_classes, :manage_workouts],
    {W.AdminClassTypeController, :create} => [:manage_settings],
    {W.AdminClassTypeController, :update} => [:manage_settings],
    {W.AdminClassTypeController, :delete} => [:manage_settings],
    {W.AdminScaleLevelController, :index} => [:manage_workouts, :manage_settings],
    {W.AdminScaleLevelController, :update} => [:manage_settings],

    # Schedule
    {W.AdminScheduleController, :create_slot} => [:manage_schedule],
    {W.AdminScheduleController, :create_series} => [:manage_schedule],
    {W.AdminScheduleController, :update_slot} => [:manage_schedule],
    {W.AdminScheduleController, :delete_slot} => [:manage_schedule],
    {W.AdminScheduleController, :approve_booking} => [:run_classes],
    {W.AdminScheduleController, :reject_booking} => [:run_classes],
    {W.AdminScheduleController, :record_attendance} => [:run_classes],

    # Finance
    {W.AdminFinanceController, :summary} => [:view_finance_reports],
    {W.AdminFinanceController, :operational_queues} => [:view_finance_reports],
    {W.AdminFinanceController, :cleanup_records} => [:manage_billing],
    {W.AdminFinanceController, :purge_record} => [:manage_billing],
    {W.AdminFinanceController, :packages} => [:view_package_catalog],
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

    # Staff appointments: front desk books and cancels for clients.
    {W.AppointmentsController, :slots} => [:manage_appointments, :book_for_clients],
    {W.AppointmentsController, :book_for_client} => [:manage_appointments, :book_for_clients],
    {W.AppointmentsController, :cancel} => [:manage_appointments, :book_for_clients],

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
    {W.OrganizationAccessController, :revoke} => [:invite_clients]
  }

  @doc "Capabilities that each grant the route, or nil when unlisted."
  def for_action(controller, action) do
    Map.get(@actions, {controller, action}) || Map.get(@controller_defaults, controller)
  end
end
