defmodule Palee.Application.CreateFinanceReferralProgram do
  alias Palee.Application.CoveringBranches
  alias Palee.Finance

  def call(params), do: Finance.create_referral_program(params)

  @doc "ADR-186 §8: the referral programme is business-wide, so all-branch staff only."
  def call(context, params) do
    with :ok <- CoveringBranches.authorize(context, :all),
         do: Finance.create_referral_program(context, params)
  end
end
