defmodule Palee.Application.ListFinanceReferralPrograms do
  alias Palee.Finance

  def call, do: {:ok, %{referral_programs: Finance.list_referral_programs()}}
end
