defmodule Palee.Finance.Queries.ListMemberOffers do
  @moduledoc "The promotion codes the box shows its members on `today` (`MemberOffers`)."

  alias Palee.Finance.Domain.MemberOffers
  alias Palee.Finance.FinanceStore

  def call(%Date{} = today) do
    {campaigns, codes} = FinanceStore.list_member_visible_promotions()
    MemberOffers.available(campaigns, codes, today)
  end
end
