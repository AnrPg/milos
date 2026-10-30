defmodule Palee.Application.Documents.BookingGate do
  @moduledoc """
  The documents check of the booking flow (ADR-252). A client booking a
  class, joining a waitlist or booking an appointment for themselves is
  refused with `{:error, :documents_required, %{documents,
  health_certificate}}` when, under the box's settings, a mandatory
  document is unsigned (on by default) or their health certificate is
  missing or expired (off by default).

  Only clients are checked: staff booking themselves, and staff placing a
  client in a class, are never stopped here.
  """

  alias Palee.{Documents, Organizations}

  def check(context, user_id, now \\ DateTime.utc_now())

  def check(%{organization_id: organization_id} = context, user_id, now)
      when is_binary(organization_id) and is_binary(user_id) do
    if Organizations.client_role(context, user_id),
      do: Documents.booking_gate(context, user_id, Organizations.local_date(context, now)),
      else: :ok
  end

  def check(_context, _user_id, _now), do: :ok
end
