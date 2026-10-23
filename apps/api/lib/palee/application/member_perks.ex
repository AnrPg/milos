defmodule Palee.Application.MemberPerks do
  @moduledoc """
  A member's partner perks (ADR-191) across every provider they are a
  client of: the perks they can use, claiming one (which reveals its code
  or QR and is recorded), their claims, and a fresh verification link for
  a QR claim.

  Like `MyProviders` (ADR-162), each provider is read in its own tenant
  context as the member. Only providers where the person holds a client
  role (member, athlete) count, never ones where they are staff only, and
  never a business in demo mode (ADR-184). A provider that fails to read is
  left out, never the whole list.

  `for_member_provider/1` is the shape `GET /api/me/billing` puts in each
  provider's `perks` array (`BillingPerk`).
  """

  require Logger

  alias Palee.Application.{MyProviders, PerkPresenter, Perks, SignedToken}
  alias Palee.Organizations
  alias Palee.Perks, as: PerksContext

  @client_roles ~w(member athlete)
  @link_salt "perk-verification-v1"

  @doc "The salt verification links are signed with (shared with `PerkVerification`)."
  def link_salt, do: @link_salt

  @doc "`GET /api/me/perks`: the perks the member can see at every provider, with their claim."
  def list(context) do
    perks =
      context
      |> client_tenants()
      |> Enum.flat_map(fn {provider, tenant} -> safe(provider, fn -> provider_perks(tenant, provider) end) end)

    {:ok, %{perks: perks}}
  end

  @doc "`GET /api/me/perks/claims`: the member's claims at every provider, newest first."
  def claims(context) do
    claims =
      context
      |> client_tenants()
      |> Enum.flat_map(fn {provider, tenant} ->
        safe(provider, fn -> provider_claims(tenant, provider) end)
      end)
      |> Enum.sort_by(& &1.claimed_at, {:desc, DateTime})

    {:ok, %{claims: claims}}
  end

  @doc """
  `POST /api/me/perks/:id/claim`: claims a perk, or returns the member's
  unused claim of it (claiming twice is safe). A QR claim comes with a
  fresh verification link.
  """
  def claim(context, perk_id) do
    with {:ok, provider, tenant, perk} <- find_perk(context, perk_id),
         facts = member_facts(tenant),
         true <- PerksContext.for_member?(perk, facts) || {:error, :not_found} do
      today = Perks.today(tenant)
      now = DateTime.utc_now()
      {nonce, token_hash} = PerksContext.new_secret()

      decide = fn locked, %{member_claims: count, open_claim: open} ->
        cond do
          open -> {:existing, open}
          true -> decide_new(locked, count, today, now, token_hash)
        end
      end

      with {:ok, %{perk: perk, claim: claim, new?: new?}} <-
             PerksContext.claim(tenant, perk.id, tenant.user_id, decide),
           {:ok, claim, nonce} <- link_secret(tenant, perk, claim, new?, nonce) do
        if new?, do: Perks.track_claim("perk_claimed", tenant, perk, claim, %{})

        {:ok,
         %{
           claim: present_claim(tenant, provider, perk, claim, nonce, today),
           created: new?
         }}
      end
    end
  end

  defp decide_new(perk, count, today, now, token_hash) do
    with :ok <- PerksContext.claim_check(perk, %{today: today, member_claims: count}) do
      {:new, new_claim_attrs(perk, now, token_hash)}
    end
  end

  defp new_claim_attrs(%{redemption_method: "shared_code"} = perk, now, _hash),
    do: %{code: perk.shared_code, claimed_at: now}

  # The adapter puts the pool code in.
  defp new_claim_attrs(%{redemption_method: "unique_code"}, now, _hash), do: %{claimed_at: now}

  defp new_claim_attrs(%{redemption_method: "qr"}, now, hash),
    do: %{code: PerksContext.display_code(), token_hash: hash, claimed_at: now}

  # A new QR claim already holds the secret; an existing one gets a new one.
  defp link_secret(_tenant, %{redemption_method: "qr"}, claim, true, nonce), do: {:ok, claim, nonce}

  defp link_secret(tenant, %{redemption_method: "qr"}, %{status: "claimed"} = claim, false, _nonce) do
    {nonce, hash} = PerksContext.new_secret()

    with {:ok, claim} <- PerksContext.rotate_token(tenant, claim.id, tenant.user_id, hash),
         do: {:ok, claim, nonce}
  end

  defp link_secret(_tenant, _perk, claim, _new?, _nonce), do: {:ok, claim, nil}

  @doc """
  `POST /api/me/perks/claims/:id/verification-link`: a new short-lived link
  for the QR of an unused claim; the previous link stops working.
  """
  def verification_link(context, claim_id) do
    with {:ok, provider, tenant, claim} <- find_claim(context, claim_id),
         %{} = perk <- PerksContext.get_perk(tenant, claim.perk_id) || {:error, :not_found},
         :ok <- qr(perk),
         today = Perks.today(tenant),
         :ok <- Perks.usable(perk, claim, today),
         {nonce, hash} = PerksContext.new_secret(),
         {:ok, claim} <- PerksContext.rotate_token(tenant, claim.id, tenant.user_id, hash) do
      {:ok, %{claim: present_claim(tenant, provider, perk, claim, nonce, today)}}
    end
  end

  defp qr(%{redemption_method: "qr"}), do: :ok
  defp qr(_perk), do: {:error, :perk_not_qr}

  @doc """
  The billing slot (`GET /api/me/billing`, `providers[].perks`) at one
  provider, in the member's tenant context there: the perks they claimed
  and can still use, each `%{id, store, discount, code, terms,
  valid_until, url}` (`BillingPerk`). Perks not claimed yet are listed by
  `GET /api/me/perks`, since claiming is what reveals and records a code.
  """
  def for_member_provider(%{organization_id: _, user_id: user_id} = tenant) when is_binary(user_id) do
    today = Perks.today(tenant)
    claims = PerksContext.list_member_claims(tenant, user_id)
    perks = perks_by_id(tenant, Enum.map(claims, & &1.perk_id))

    claims
    |> Enum.filter(&(&1.status == "claimed"))
    |> Enum.flat_map(fn claim ->
      case Map.get(perks, claim.perk_id) do
        nil -> []
        perk -> if PerksContext.usable?(perk, claim, today), do: [{perk, claim}], else: []
      end
    end)
    |> Enum.uniq_by(fn {perk, _claim} -> perk.id end)
    |> Enum.map(fn {perk, claim} ->
      %{
        id: perk.id,
        store: perk.partner_name,
        discount: PerksContext.benefit_label(perk),
        code: claim.code,
        terms: perk.terms,
        valid_until: perk.valid_until,
        url: perk.partner_url
      }
    end)
  end

  @doc "The same, from the person's own context and a provider id."
  def for_member_provider(context, organization_id) do
    with {:ok, tenant} <- MyProviders.tenant_context(context, organization_id),
         true <- client_tenant?(tenant) do
      for_member_provider(tenant)
    else
      _not_a_client -> []
    end
  end

  # -- reading -------------------------------------------------------------

  defp provider_perks(tenant, provider) do
    today = Perks.today(tenant)
    facts = member_facts(tenant)
    claims = PerksContext.list_member_claims(tenant, tenant.user_id)
    by_perk = Enum.group_by(claims, & &1.perk_id)
    live = tenant |> PerksContext.list_perks(%{statuses: ["published"]}) |> Enum.filter(&PerksContext.live?(&1, today))
    logos = PerkPresenter.logos(live)

    live
    |> Enum.filter(&PerksContext.for_member?(&1, facts))
    |> Enum.map(fn perk ->
      mine = Map.get(by_perk, perk.id, [])
      counted = Enum.count(mine, &(&1.status != "revoked"))
      open = Enum.find(mine, &(&1.status == "claimed"))

      availability =
        if open,
          do: :ok,
          else: PerksContext.claim_check(perk, %{today: today, member_claims: counted})

      perk
      |> PerkPresenter.common(logos, today)
      |> Map.merge(%{
        provider: provider_summary(provider),
        claimable: availability == :ok,
        unavailable_reason: reason(availability),
        claim: open && present_claim(tenant, provider, perk, open, nil, today)
      })
    end)
  end

  defp provider_claims(tenant, provider) do
    today = Perks.today(tenant)
    claims = PerksContext.list_member_claims(tenant, tenant.user_id)
    perks = perks_by_id(tenant, Enum.map(claims, & &1.perk_id))

    Enum.flat_map(claims, fn claim ->
      case Map.get(perks, claim.perk_id) do
        nil -> []
        perk -> [present_claim(tenant, provider, perk, claim, nil, today)]
      end
    end)
  end

  defp perks_by_id(_tenant, []), do: %{}

  defp perks_by_id(tenant, ids),
    do: tenant |> PerksContext.list_perks(%{ids: Enum.uniq(ids)}) |> Map.new(&{&1.id, &1})

  defp reason(:ok), do: nil
  defp reason({:error, reason}), do: Atom.to_string(reason)

  defp present_claim(tenant, provider, perk, claim, nonce, today) do
    %{
      id: claim.id,
      perk_id: perk.id,
      organization_id: perk.organization_id,
      provider: provider_summary(provider),
      partner_name: perk.partner_name,
      benefit_label: PerksContext.benefit_label(perk),
      redemption_method: perk.redemption_method,
      terms: perk.terms,
      valid_until: perk.valid_until,
      partner_url: perk.partner_url,
      code: claim.code,
      status: claim.status,
      usable: PerksContext.usable?(perk, claim, today),
      claimed_at: claim.claimed_at,
      used_at: claim.used_at,
      verification: verification(tenant, perk, claim, nonce)
    }
  end

  defp verification(tenant, %{redemption_method: "qr"} = perk, %{status: "claimed"} = claim, nonce)
       when is_binary(nonce) do
    case PerksContext.link_expires_at(DateTime.utc_now(), perk.valid_until) do
      {:ok, expires_at} ->
        token =
          SignedToken.sign(
            @link_salt,
            PerksContext.link_payload(claim.id, tenant.organization_id, nonce, expires_at)
          )

        %{token: token, path: "/perks/verify/" <> token, expires_at: expires_at}

      {:error, _ended} ->
        nil
    end
  end

  defp verification(_tenant, _perk, _claim, _nonce), do: nil

  defp provider_summary(provider),
    do: Map.take(provider, [:organization_id, :name, :slug, :kind, :logo_url])

  defp member_facts(tenant) do
    %{
      package_ids: PerksContext.member_package_ids(tenant, tenant.user_id, Perks.today(tenant)),
      home_location_id: tenant.membership && Map.get(tenant.membership, :home_location_id)
    }
  end

  # -- finding -------------------------------------------------------------

  defp find_perk(context, perk_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(perk_id) do
      context
      |> client_tenants()
      |> Enum.find_value({:error, :not_found}, fn {provider, tenant} ->
        case PerksContext.get_perk(tenant, perk_id) do
          %{status: "published"} = perk -> {:ok, provider, tenant, perk}
          _other -> nil
        end
      end)
    else
      :error -> {:error, :not_found}
    end
  end

  defp find_claim(context, claim_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(claim_id) do
      context
      |> client_tenants()
      |> Enum.find_value({:error, :not_found}, fn {provider, tenant} ->
        case PerksContext.get_claim(tenant, claim_id) do
          %{user_id: user_id} = claim when user_id == tenant.user_id -> {:ok, provider, tenant, claim}
          _other -> nil
        end
      end)
    else
      :error -> {:error, :not_found}
    end
  end

  @doc "The providers the person is a client of (not demo businesses), each with its tenant."
  def client_tenants(%{user_id: user_id} = context) when is_binary(user_id) do
    {active, _former} =
      context |> Organizations.list_my_providers() |> Organizations.split_providers()

    active
    |> Enum.filter(&client?/1)
    |> Enum.flat_map(fn provider ->
      case MyProviders.tenant_context(context, provider.organization_id) do
        {:ok, tenant} -> if client_tenant?(tenant), do: [{provider, tenant}], else: []
        _error -> []
      end
    end)
  end

  def client_tenants(_context), do: []

  defp client?(%{roles: roles}) when is_list(roles), do: Enum.any?(roles, &(to_string(&1) in @client_roles))
  defp client?(_provider), do: false

  defp client_tenant?(tenant),
    do:
      not Organizations.business_gated?(tenant) and
        Enum.any?(tenant.roles || [], &(to_string(&1) in @client_roles))

  defp safe(provider, fun) do
    fun.()
  rescue
    error ->
      Logger.error(
        "member_perks_provider_failed organization_id=#{provider.organization_id} " <>
          Exception.format(:error, error, __STACKTRACE__)
      )

      []
  end
end
