defmodule MilosTraining.Application.ListFinanceReferralPrograms do
  alias MilosTraining.Finance

  def call, do: {:ok, %{referral_programs: Finance.list_referral_programs()}}
end
