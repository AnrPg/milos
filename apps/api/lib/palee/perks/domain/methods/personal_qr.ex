defmodule Palee.Perks.Domain.Methods.PersonalQr do
  @moduledoc """
  A personal single-use QR Palee issues (ADR-191 §5). The QR opens a
  signed, expiring link (`VerificationToken`) the partner uses, without an
  account, to see the perk, whether it is valid or used and the member's
  first name, and to mark it used once. The short code under the QR is for
  a counter whose camera won't scan.
  """
  @behaviour Palee.Perks.Domain.RedemptionMethod

  @impl true
  def key, do: "personal_qr"
  @impl true
  def validate(_settings), do: []
  @impl true
  def issue, do: :reference
  @impl true
  def verifiable?, do: true
  @impl true
  def ready(_facts), do: :ok
  @impl true
  def reveal(_settings, code), do: %{code: code, url: nil, show_membership: false}
end
