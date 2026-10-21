defmodule Palee.Finance.Commands.FinalizeEntitlementSource do
  alias Palee.Finance.FinanceStore

  def call(user_id, source_context, source_id, allowance, params),
    do:
      FinanceStore.transition_entitlement_source(
        user_id,
        source_context,
        source_id,
        allowance,
        :finalize,
        params
      )
end
