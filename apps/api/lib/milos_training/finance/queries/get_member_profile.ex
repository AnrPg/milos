defmodule MilosTraining.Finance.Queries.GetMemberProfile do
  alias MilosTraining.Finance.FinanceStore

  def call(user_id), do: FinanceStore.get_member_profile(user_id)
end
