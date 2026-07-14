defmodule MilosTraining.Application.UpdateFinanceReferralStatus do
  alias MilosTraining.Application.RecordAnalyticsEvent
  alias MilosTraining.Finance

  def call(id, status) do
    with {:ok, event} <- Finance.update_referral_status(id, status) do
      RecordAnalyticsEvent.call_unsafe("referral_status_changed", %{
        user_id: event.referred_user_id,
        context_type: "referral_event",
        context_id: event.id,
        metadata: %{
          referral_program_id: event.referral_program_id,
          referrer_user_id: event.referrer_user_id,
          membership_id: event.membership_id,
          status: event.status
        }
      })

      {:ok, event}
    end
  end
end
