defmodule Palee.Application.PerkVerification do
  @moduledoc """
  The partner's side of a Palee-issued personal QR (ADR-191 §5): the
  counter scans the member's QR, opens the link and sees whether it is
  good; one tap marks it used. No account: the link is the credential, so
  it is

    * signed (`SignedToken`, the endpoint secret) — nobody can make or edit
      one;
    * expiring — its own expiry (`Perks.link_max_seconds/0` at most, never
      past the perk's last day) and the signer's `max_age`;
    * revocable — bound to the claim's current secret (the stored SHA-256
      of the nonce, compared in constant time): the business revoking the
      claim, or the member opening a new QR, ends it;
    * single-use — marking it used is a conditional write under a lock on
      the perk, recorded as an analytics event (the audit trail) with
      `[:palee, :perk, :redeemed]` telemetry;
    * rate limited at the route.

  It shows the minimum the counter needs: the perk, valid or used, and the
  member's first name. Every failure of the token itself answers the same
  `invalid_verification_link`, so the answer says nothing about which
  check failed.
  """

  alias Palee.Application.{MemberPerks, Perks, SignedToken}
  alias Palee.Organizations
  alias Palee.Perks, as: PerksContext

  @doc "`GET /api/public/perk-verifications/:token`."
  def inspect_link(token, now \\ DateTime.utc_now()) do
    with {:ok, tenant, claim, perk} <- resolve(token, now) do
      {:ok, present(tenant, perk, claim)}
    end
  end

  @doc "`POST /api/public/perk-verifications/:token/redeem`: marks the claim used, once."
  def redeem(token, now \\ DateTime.utc_now()) do
    with {:ok, tenant, %{nonce: nonce} = claim, _perk} <- resolve(token, now) do
      check = fn perk, locked ->
        # Re-checked under the lock: the secret may have been replaced or the
        # claim revoked or used since `resolve/2` read it.
        cond do
          locked.status in ["used", "revoked"] -> Perks.usable(tenant, perk, locked)
          PerksContext.token_matches?(locked.token_hash, nonce) -> Perks.usable(tenant, perk, locked)
          true -> {:error, :invalid_verification_link}
        end
      end

      with {:ok, %{perk: perk, claim: used}} <-
             PerksContext.use_claim(tenant, claim.id, "partner_link", nil, now, check) do
        Perks.track_claim("perk_redeemed", nil, perk, used, %{via: "partner_link"})
        {:ok, present(tenant, perk, used)}
      end
    end
  end

  # A good token names a personal-QR claim of its organization whose
  # current secret it carries (a used claim no longer has one and answers
  # as used; a revoked one keeps it and answers as revoked).
  defp resolve(token, now) when is_binary(token) and byte_size(token) <= 2_048 do
    with {:ok, payload} <-
           MemberPerks.link_salt()
           |> SignedToken.verify(token, max_age: PerksContext.link_max_seconds())
           |> normalize_verify(),
         {:ok, %{claim_id: claim_id, organization_id: organization_id, nonce: nonce}} <-
           PerksContext.parse_link(payload, now),
         tenant = %{organization_id: organization_id},
         %{} = claim <- PerksContext.get_claim(tenant, claim_id) || invalid(),
         true <- current?(claim, nonce) || invalid(),
         %{} = perk <- PerksContext.get_perk(tenant, claim.perk_id) || invalid(),
         true <- PerksContext.method_verifiable?(perk.redemption_method) || invalid() do
      {:ok, tenant, Map.put(claim, :nonce, nonce), perk}
    end
  end

  defp resolve(_token, _now), do: invalid()

  defp current?(%{status: "used"}, _nonce), do: true
  defp current?(claim, nonce), do: PerksContext.token_matches?(claim.token_hash, nonce)

  defp invalid, do: {:error, :invalid_verification_link}

  defp normalize_verify({:ok, payload}), do: {:ok, payload}
  defp normalize_verify({:error, :expired}), do: {:error, :verification_link_expired}
  defp normalize_verify(_invalid), do: invalid()

  defp present(tenant, perk, claim) do
    business = Organizations.brand_summary(tenant.organization_id) || %{}
    version = version_of(tenant, perk, claim)

    %{
      status: status(tenant, perk, claim),
      code: claim.code,
      member_first_name: PerksContext.member_first_name(tenant, claim.user_id),
      claimed_at: claim.claimed_at,
      used_at: claim.used_at,
      perk: %{
        partner_name: perk.partner_name,
        benefit_label: PerksContext.benefit_label(version.benefit),
        terms: version.terms,
        valid_until: perk.valid_until
      },
      business: %{name: Map.get(business, :name), logo_url: Map.get(business, :logo_url)}
    }
  end

  defp version_of(tenant, perk, claim) do
    if claim.perk_version == perk.current_version do
      perk.version
    else
      tenant
      |> PerksContext.get_versions([{perk.id, claim.perk_version}])
      |> Map.get({perk.id, claim.perk_version}, perk.version)
    end
  end

  defp status(_tenant, _perk, %{status: "used"}), do: "used"
  defp status(_tenant, _perk, %{status: "revoked"}), do: "revoked"

  defp status(tenant, perk, claim) do
    case Perks.usable(tenant, perk, claim) do
      :ok -> "valid"
      {:error, :perk_outside_hours} -> "outside_hours"
      _ended -> "expired"
    end
  end
end
