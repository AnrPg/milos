defmodule Palee.Partners.Domain.BadgePolicy do
  @moduledoc """
  Which badge a deck card shows (ADR-280, «Card»). Pure.

  - `box` «✓ Μέλος <box>»: an active membership and the person left
    «Δείξε το box μου» on (the default);
  - `member` «✓ Μέλος box»: an active membership, `show_box` off (the box
    is never named);
  - `verified` «✓ Επαληθευμένος»: verified through a membership that has
    since ended (verification never lapses);
  - `sponsors` «✓ Με εγγυητές»: verified by two sponsors and the Palee team.

  `verification` is what `PartnerEligibility.verification_badges/1` says of
  the person: the method and the box of an active membership (nil if none),
  without `show_box` applied.
  """

  @kinds ~w(box member verified sponsors)

  def kinds, do: @kinds

  @doc "The card's badge, or nil for someone not verified."
  def badge(%{box_name: box_name}, show_box) when is_binary(box_name) and box_name != "" do
    if show_box == false,
      do: %{kind: "member", box_name: nil},
      else: %{kind: "box", box_name: box_name}
  end

  def badge(%{method: "membership"}, _show_box), do: %{kind: "verified", box_name: nil}
  def badge(%{method: "sponsors"}, _show_box), do: %{kind: "sponsors", box_name: nil}
  def badge(_verification, _show_box), do: nil
end
