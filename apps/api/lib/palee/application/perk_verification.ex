defmodule Palee.Application.PerkVerification do
  @moduledoc """
  The partner's side of a QR perk (ADR-191 §3): the counter scans the
  member's QR, opens the link and sees whether it is good; one tap marks it
  used. No account: the link is the credential, so it is

    * signed (`SignedToken`, the endpoint secret) — nobody can make or edit
      one;
    * short-lived — its own expiry (`Perks.link_max_seconds/0` at most,
      never past the perk's last day) and the signer's `max_age`;
    * bound to the claim's current secret — the stored SHA-256 of the
      nonce is compared in constant time, so a link replaced by a newer one
      (the member reopened the QR) or a revoked claim stops working;
    * single-use — marking it used is a conditional write under a lock on
      the perk, so two scans at once give one use and one
      `perk_claim_already_used`.

  What it shows is the least the counter needs: the perk, the business and
  the short code under the QR; never who the member is. Every failure of
  the token itself answers the same `invalid_verification_link`, so the
  answer says nothing about which check failed.
  """

  alias Palee.Application.{MemberPerks, Perks, SignedToken}
  alias Palee.Organizations
  alias Palee.Perks, as: PerksContext

  @doc "`GET /api/public/perk-verifications/:token`."
  def inspect_link(token, now \\ DateTime.utc_now()) do
    with {:ok, tenant, claim} <- resolve(token, now),
         %{} = perk <- PerksContext.get_perk(tenant, claim.perk_id) || {:error, :invalid_verification_link} do
      {:ok, present(tenant, perk, claim, Perks.today(tenant))}
    end
  end

  @doc "`POST /api/public/perk-verifications/:token/redeem`: marks the claim used, once."
  def redeem(token, now \\ DateTime.utc_now()) do
    with {:ok, tenant, %{nonce: nonce} = claim} <- resolve(token, now) do
      today = Perks.today(tenant)

      check = fn perk, locked ->
        # Re-checked under the lock: the secret may have been replaced or the
        # claim revoked since `resolve/2` read it.
        if PerksContext.token_matches?(locked.token_hash, nonce) or locked.status == "used",
          do: Perks.usable(perk, locked, today),
          else: {:error, :invalid_verification_link}
      end

      with {:ok, %{perk: perk, claim: used}} <-
             PerksContext.use_claim(tenant, claim.id, "partner_link", nil, now, check) do
        Perks.track_claim("perk_redeemed", nil, perk, used, %{via: "partner_link"})
        {:ok, present(tenant, perk, used, today)}
      end
    end
  end

  # A good token names a claim of its organization whose current secret it
  # carries (a used claim no longer has one, and answers as used).
  defp resolve(token, now) when is_binary(token) and byte_size(token) <= 2_048 do
    with {:ok, payload} <-
           SignedToken.verify(MemberPerks.link_salt(), token,
             max_age: PerksContext.link_max_seconds()
           )
           |> normalize_verify(),
         {:ok, %{claim_id: claim_id, organization_id: organization_id, nonce: nonce}} <-
           PerksContext.parse_link(payload, now),
         tenant = %{organization_id: organization_id},
         %{} = claim <- PerksContext.get_claim(tenant, claim_id) || {:error, :invalid_verification_link},
         true <-
           (PerksContext.token_matches?(claim.token_hash, nonce) or claim.status == "used") ||
             {:error, :invalid_verification_link} do
      {:ok, tenant, Map.put(claim, :nonce, nonce)}
    end
  end

  defp resolve(_token, _now), do: {:error, :invalid_verification_link}

  defp normalize_verify({:ok, payload}), do: {:ok, payload}
  defp normalize_verify({:error, :expired}), do: {:error, :verification_link_expired}
  defp normalize_verify(_invalid), do: {:error, :invalid_verification_link}

  defp present(tenant, perk, claim, today) do
    business = Organizations.brand_summary(tenant.organization_id) || %{}

    %{
      status: status(perk, claim, today),
      code: claim.code,
      claimed_at: claim.claimed_at,
      used_at: claim.used_at,
      perk: %{
        partner_name: perk.partner_name,
        benefit_label: PerksContext.benefit_label(perk),
        terms: perk.terms,
        valid_until: perk.valid_until
      },
      business: %{name: Map.get(business, :name), logo_url: Map.get(business, :logo_url)}
    }
  end

  defp status(_perk, %{status: "used"}, _today), do: "used"
  defp status(_perk, %{status: "revoked"}, _today), do: "revoked"

  defp status(perk, claim, today),
    do: if(PerksContext.usable?(perk, claim, today), do: "valid", else: "expired")
end
