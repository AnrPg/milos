defmodule Palee.Application.UpdateFinanceReferralProgram do
  alias Palee.Application.CoveringBranches
  alias Palee.Finance

  def call(id, params), do: Finance.update_referral_program(id, params)

  @doc "ADR-186 §8: the referral programme is business-wide, so all-branch staff only."
  def call(context, id, params) do
    with :ok <- CoveringBranches.authorize(context, :all),
         do: Finance.update_referral_program(context, id, params)
  end
end
