defmodule Palee.Finance.Queries.ListReferralPrograms do
  alias Palee.Finance.FinanceStore

  def call, do: FinanceStore.list_referral_programs()
end
