defmodule Palee.Application.ConnectedDevices do
  @moduledoc """
  Εγώ › Συνδεδεμένες συσκευές (ADR-155, decision 7; vision §8): the person's
  Wallet cards at every box (platform, when added, revoke), whether each
  Wallet platform can issue cards on this server, the calendar (ICS) feed
  links (reset with `POST /api/calendar/export-links/regenerate`), and the
  health integrations.

  Nothing here pretends: Garmin (ADR-161) is `unavailable` («Σύντομα») on a
  server without Garmin credentials, and otherwise shows its connection
  (status, last sync, what syncs, history import, error); Apple Health and
  Health Connect are `native_only` until the store app connects them, then
  `connected` with their last sync (ADR-172).
  """

  alias Palee.Application.{
    GarminConnection,
    GetCalendarExportLinks,
    PhoneHealthConnection,
    WalletPasses
  }

  def call(%{user_id: _} = context, account) do
    with {:ok, calendar} <- GetCalendarExportLinks.call(account) do
      {:ok,
       %{
         wallet: %{
           platforms: WalletPasses.availability(),
           passes: WalletPasses.mine(context)
         },
         calendar: Map.take(calendar, [:https_url, :webcal_url, :download_url, :help]),
         integrations: [
           GarminConnection.row(context),
           PhoneHealthConnection.row(context, "apple_health"),
           PhoneHealthConnection.row(context, "health_connect")
         ]
       }}
    end
  end
end
