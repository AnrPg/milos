defmodule Palee.Facility.Domain.MemberCodePolicy do
  @moduledoc """
  The owner's choice of personal code, «Ρυθμίσεις › Check-in» (board 10, Q5;
  ADR-155), as pure rules:

    * `rotating` (default): the in-app QR changes every 30 seconds
      (`MemberCode`). A Wallet card would freeze one code, so Wallet is not
      offered (`wallet_requires_static_code`).
    * `static`: each member has one persistent, revocable code
      (`StaticMemberCode`), shown in the app and carried by the Wallet card.
      The member can reset it and staff can revoke it; either voids the
      Wallet cards issued for it.

  The desk accepts both kinds of code: a rotating code is always fine (it
  proves the member's phone is at the desk now), a static one only while the
  box keeps static codes. Switching to `static` issues codes lazily, the
  first time a member opens their QR; switching back to `rotating` revokes
  every static code and the cards that carry it.
  """

  @type mode :: String.t()
  @type kind :: :rotating | :static_app | :static_wallet

  def modes, do: ~w(rotating static)

  @doc "The mode in effect for a box's rules."
  def mode(%{member_code_mode: "static"}), do: "static"
  def mode(_rules), do: "rotating"

  @doc "What the member's QR is in this mode."
  def presented_kind(rules), do: if(mode(rules) == "static", do: :static, else: :rotating)

  @doc "Whether Wallet cards may be issued."
  def wallet_allowed(rules) do
    if mode(rules) == "static", do: :ok, else: {:error, :wallet_requires_static_code}
  end

  @doc "What kind of personal code a scanned string claims to be, by its prefix."
  def kind("M1" <> _rest), do: :rotating
  def kind("S1" <> _rest), do: :static_app
  def kind("W1" <> _rest), do: :static_wallet
  def kind(_code), do: nil

  @doc "Whether the desk takes this kind of code in this mode."
  def accept(_rules, :rotating), do: :ok

  def accept(rules, kind) when kind in [:static_app, :static_wallet] do
    if mode(rules) == "static", do: :ok, else: {:error, :invalid_member_code}
  end

  def accept(_rules, _kind), do: {:error, :invalid_member_code}

  @doc "The check-in method a kind of code records."
  def method(:static_wallet), do: "wallet"
  def method(_kind), do: "member_qr"

  @doc "What a change of mode requires: revoking static codes, or nothing."
  def on_change(before_rules, after_rules) do
    if mode(before_rules) == "static" and mode(after_rules) == "rotating",
      do: :revoke_static_codes,
      else: :none
  end
end
