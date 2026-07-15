defmodule MilosTraining.Finance.Commands.ReleaseEntitlementSource do
  alias MilosTraining.Finance.FinanceStore

  def call(user_id, source_context, source_id, allowance, params),
    do:
      FinanceStore.transition_entitlement_source(
        user_id,
        source_context,
        source_id,
        allowance,
        :release,
        params
      )
end
