defmodule Palee.Application.WalletReactions do
  @moduledoc """
  Keeps Wallet cards current (ADR-155): a booking made or cancelled, or a
  check-in, changes the member's next booking, so their cards at that box
  are marked updated and the platforms are told (in a background job).
  Most members have no card; then this is one indexed update that matches
  nothing.
  """

  @behaviour Palee.DomainEvents.Handler

  alias Palee.Application.WalletPasses

  @impl true
  def handle_event(event, %{organization_id: organization_id, user_id: user_id})
      when event in [:booking_made, :booking_cancelled, :attendance_recorded] and
             is_binary(organization_id) and is_binary(user_id) do
    WalletPasses.touch(%{organization_id: organization_id}, user_id)
  end

  def handle_event(_event, _payload), do: :ok
end
