defmodule Palee.Application.UpdateCheckInRules do
  @moduledoc """
  «Ρυθμίσεις › Check-in» (ADR-155, decision 6): validates and saves the
  owner's rules, then carries out what a change of personal-code mode
  requires (`MemberCodePolicy.on_change/2`): going back to rotating codes
  revokes every static code and the Wallet cards that carry it.
  """

  alias Palee.Application.MemberCodes
  alias Palee.Facility
  alias Palee.Facility.Domain.MemberCodePolicy

  def call(context, attrs, now \\ DateTime.utc_now()) do
    before = Facility.check_in_rules(context)

    with {:ok, rules} <- Facility.update_check_in_rules(context, attrs) do
      case MemberCodePolicy.on_change(before, rules) do
        :revoke_static_codes -> {:ok, _counts} = MemberCodes.revoke_all(context, now)
        :none -> :ok
      end

      {:ok, rules}
    end
  end
end
