defmodule Palee.Organizations.Commands.CreateCoachPractice do
  @moduledoc """
  ADR-170: any account opens its own practice as an independent coach (vision
  §7.10): a one-person organization of kind `coach`, owned by the account,
  who is also its coach. Since ADR-184 the practice starts in demo mode,
  like every self-serve business (`CreateBusinessAccount`).

  One practice per account: a second one is refused while the first is
  active, so self-serve sign-up cannot be used to spray organizations.
  """

  alias Palee.Organizations.Commands.CreateBusinessAccount

  def call(account, params, opts \\ []),
    do: CreateBusinessAccount.call(account, "coach", params, opts)
end
