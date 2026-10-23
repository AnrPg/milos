defmodule Palee.Application.MemberPerks do
  @moduledoc """
  A member's partner perks (ADR-191) across every provider they are a
  client of: the perks they can use, claiming one (which reveals its code,
  link or QR and is recorded under the current version), their claims, and
  a fresh verification link for a personal QR.

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
      |> Enum.flat_map(fn {provider, tenant} ->
        safe(provider, fn -> provider_perks(tenant, provider) end)
      end)

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
  unused claim of it (claiming twice is safe). A personal QR comes with a
  fresh verification link.
  """
  def claim(context, perk_id) do
    with {:ok, provider, tenant, perk} <- find_perk(context, perk_id),
         facts = member_facts(tenant),
         true <- PerksContext.for_member?(perk, facts) || {:error, :not_found} do
      today = facts.today
      local_now = Perks.local_now(tenant)
      now = DateTime.utc_now()
      {nonce, token_hash} = PerksContext.new_secret()

      decide = fn locked, %{member_claims: count, open_claim: open, count_since: count_since} ->
        if open do
          {:existing, open}
        else
          period =
            case PerksContext.period_start(locked.version.rules, local_now) do
              nil -> nil
              start -> count_since.(Perks.to_utc(tenant, start))
            end

          check = %{today: today, local_now: local_now, member_claims: count, period: period}

          with :ok <- PerksContext.claim_check(locked, check),
               do: {:new, new_claim_attrs(locked, now, token_hash)}
        end
      end

      with {:ok, %{perk: perk, claim: claim, new?: new?, free_codes: free}} <-
             PerksContext.claim(tenant, perk.id, tenant.user_id, decide),
           {:ok, claim, nonce} <- link_secret(tenant, perk, claim, new?, nonce) do
        if new?, do: after_claim(tenant, perk, claim, free)
        version = version_of(tenant, perk, claim)

        {:ok,
         %{
           claim: present_claim(tenant, provider, perk, version, claim, nonce, today, local_now),
           created: new?
         }}
      end
    end
  end

  defp new_claim_attrs(perk, now, token_hash) do
    base = %{claimed_at: now}

    attrs =
      case PerksContext.method_issue(perk.redemption_method) do
        :shared ->
          Map.put(base, :code, perk.version.redemption.shared_code || PerksContext.display_code())

        :pool ->
          Map.put(base, :issue, :pool)

        :reference ->
          Map.put(base, :code, PerksContext.display_code())
      end

    if PerksContext.method_verifiable?(perk.redemption_method),
      do: Map.put(attrs, :token_hash, token_hash),
      else: attrs
  end

  defp after_claim(tenant, perk, claim, free) do
    Perks.track_claim("perk_claimed", tenant, perk, claim, %{})

    if is_integer(free) and
         PerksContext.pool_low?(Map.from_struct(perk.version.redemption), free) do
      Perks.track_claim("perk_pool_low", tenant, perk, claim, %{free_codes: free})
    end
  end

  # A new QR claim already holds the secret; an existing one gets a new one.
  defp link_secret(tenant, perk, claim, new?, nonce) do
    cond do
      not PerksContext.method_verifiable?(perk.redemption_method) -> {:ok, claim, nil}
      new? -> {:ok, claim, nonce}
      claim.status == "claimed" -> rotate(tenant, claim)
      true -> {:ok, claim, nil}
    end
  end

  defp rotate(tenant, claim) do
    {nonce, hash} = PerksContext.new_secret()

    with {:ok, claim} <- PerksContext.rotate_token(tenant, claim.id, tenant.user_id, hash),
         do: {:ok, claim, nonce}
  end

  @doc """
  `POST /api/me/perks/claims/:id/verification-link`: a new short-lived link
  for the QR of an unused personal-QR claim; the previous link stops working.
  """
  def verification_link(context, claim_id) do
    with {:ok, provider, tenant, claim} <- find_claim(context, claim_id),
         %{} = perk <- PerksContext.get_perk(tenant, claim.perk_id) || {:error, :not_found},
         true <-
           PerksContext.method_verifiable?(perk.redemption_method) || {:error, :perk_not_qr},
         :ok <- Perks.usable(tenant, perk, claim),
         {:ok, claim, nonce} <- rotate(tenant, claim) do
      version = version_of(tenant, perk, claim)
      today = Perks.today(tenant)
      local_now = Perks.local_now(tenant)

      {:ok,
       %{claim: present_claim(tenant, provider, perk, version, claim, nonce, today, local_now)}}
    end
  end

  @doc """
  The billing slot (`GET /api/me/billing`, `providers[].perks`) at one
  provider, in the member's tenant context there: the perks they claimed
  and can still use, each `%{id, store, discount, code, terms,
  valid_until, url}` (`BillingPerk`), read from the version they agreed
  to. A link perk's `url` is the store link with the code applied. Perks
  not claimed yet are listed by `GET /api/me/perks`, since claiming is what
  reveals and records a code.
  """
  def for_member_provider(%{organization_id: _, user_id: user_id} = tenant)
      when is_binary(user_id) do
    today = Perks.today(tenant)
    local_now = Perks.local_now(tenant)

    claims =
      tenant |> PerksContext.list_member_claims(user_id) |> Enum.filter(&(&1.status == "claimed"))

    perks = perks_by_id(tenant, Enum.map(claims, & &1.perk_id))
    versions = versions(tenant, claims)

    claims
    |> Enum.flat_map(fn claim ->
      with %{} = perk <- Map.get(perks, claim.perk_id),
           %{} = version <- Map.get(versions, {claim.perk_id, claim.perk_version}),
           true <- PerksContext.usable?(perk, version.rules, claim, today, local_now) do
        [{perk, version, claim}]
      else
        _not_usable -> []
      end
    end)
    |> Enum.uniq_by(fn {perk, _version, _claim} -> perk.id end)
    |> Enum.map(fn {perk, version, claim} ->
      reveal =
        PerksContext.method_reveal(
          perk.redemption_method,
          Map.from_struct(version.redemption),
          claim.code
        )

      %{
        id: perk.id,
        store: perk.partner_name,
        discount: PerksContext.benefit_label(version.benefit),
        code: reveal.code || claim.code,
        terms: version.terms,
        valid_until: perk.valid_until,
        url: reveal.url || perk.partner_url
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
    facts = member_facts(tenant)
    today = facts.today
    local_now = Perks.local_now(tenant)
    claims = PerksContext.list_member_claims(tenant, tenant.user_id)
    by_perk = Enum.group_by(claims, & &1.perk_id)

    live =
      tenant
      |> PerksContext.list_perks(%{statuses: ["published"]})
      |> Enum.filter(&(PerksContext.live?(&1, today) and PerksContext.for_member?(&1, facts)))

    logos = PerkPresenter.logos(live)
    versions = versions(tenant, Enum.filter(claims, &(&1.status == "claimed")))

    Enum.map(live, fn perk ->
      mine = Map.get(by_perk, perk.id, [])
      open = Enum.find(mine, &(&1.status == "claimed"))

      availability =
        if open do
          :ok
        else
          PerksContext.claim_check(perk, %{
            today: today,
            local_now: local_now,
            member_claims: Enum.count(mine, &(&1.status != "revoked")),
            period: period_counts(perk, mine, tenant, local_now)
          })
        end

      claim =
        open &&
          present_claim(
            tenant,
            provider,
            perk,
            Map.get(versions, {perk.id, open.perk_version}, perk.version),
            open,
            nil,
            today,
            local_now
          )

      perk
      |> PerkPresenter.common(perk.version, logos, today)
      |> Map.merge(%{
        provider: provider_summary(provider),
        claimable: availability == :ok,
        unavailable_reason: reason(availability),
        claim: claim
      })
    end)
  end

  # For the list only (the claim itself recounts under the lock): the
  # member's own claims this period; the business-wide period cap is
  # checked when claiming.
  defp period_counts(perk, mine, tenant, local_now) do
    case PerksContext.period_start(perk.version.rules, local_now) do
      nil ->
        nil

      start ->
        since = Perks.to_utc(tenant, start)

        member =
          Enum.count(
            mine,
            &(&1.status != "revoked" and DateTime.compare(&1.claimed_at, since) != :lt)
          )

        %{member: member, all: 0}
    end
  end

  defp provider_claims(tenant, provider) do
    today = Perks.today(tenant)
    local_now = Perks.local_now(tenant)
    claims = PerksContext.list_member_claims(tenant, tenant.user_id)
    perks = perks_by_id(tenant, Enum.map(claims, & &1.perk_id))
    versions = versions(tenant, claims)

    Enum.flat_map(claims, fn claim ->
      with %{} = perk <- Map.get(perks, claim.perk_id),
           %{} = version <- Map.get(versions, {claim.perk_id, claim.perk_version}) do
        [present_claim(tenant, provider, perk, version, claim, nil, today, local_now)]
      else
        _gone -> []
      end
    end)
  end

  defp perks_by_id(_tenant, []), do: %{}

  defp perks_by_id(tenant, ids),
    do: tenant |> PerksContext.list_perks(%{ids: Enum.uniq(ids)}) |> Map.new(&{&1.id, &1})

  defp versions(tenant, claims),
    do:
      PerksContext.get_versions(
        tenant,
        claims |> Enum.map(&{&1.perk_id, &1.perk_version}) |> Enum.uniq()
      )

  defp version_of(tenant, perk, claim) do
    if claim.perk_version == perk.current_version,
      do: perk.version,
      else: tenant |> versions([claim]) |> Map.get({perk.id, claim.perk_version}, perk.version)
  end

  defp reason(:ok), do: nil
  defp reason({:error, reason}), do: Atom.to_string(reason)

  defp present_claim(tenant, provider, perk, version, claim, nonce, today, local_now) do
    reveal =
      PerksContext.method_reveal(
        perk.redemption_method,
        Map.from_struct(version.redemption),
        claim.code
      )

    %{
      id: claim.id,
      perk_id: perk.id,
      perk_version: claim.perk_version,
      organization_id: perk.organization_id,
      provider: provider_summary(provider),
      partner_name: perk.partner_name,
      benefit_label: PerksContext.benefit_label(version.benefit),
      redemption_method: perk.redemption_method,
      terms: version.terms,
      instructions: version.redemption.instructions,
      valid_until: perk.valid_until,
      partner_url: perk.partner_url,
      code: reveal.code,
      reference: claim.code,
      url: reveal.url,
      show_membership: reveal.show_membership,
      status: claim.status,
      usable: PerksContext.usable?(perk, version.rules, claim, today, local_now),
      claimed_at: claim.claimed_at,
      used_at: claim.used_at,
      verification: verification(tenant, perk, claim, nonce)
    }
  end

  defp verification(tenant, perk, %{status: "claimed"} = claim, nonce) when is_binary(nonce) do
    with true <- PerksContext.method_verifiable?(perk.redemption_method),
         {:ok, expires_at} <- PerksContext.link_expires_at(DateTime.utc_now(), perk.valid_until) do
      token =
        SignedToken.sign(
          @link_salt,
          PerksContext.link_payload(claim.id, tenant.organization_id, nonce, expires_at)
        )

      %{token: token, path: "/perks/verify/" <> token, expires_at: expires_at}
    else
      _none -> nil
    end
  end

  defp verification(_tenant, _perk, _claim, _nonce), do: nil

  defp provider_summary(provider),
    do: Map.take(provider, [:organization_id, :name, :slug, :kind, :logo_url])

  defp member_facts(tenant) do
    today = Perks.today(tenant)
    membership = tenant.membership

    %{
      today: today,
      package_ids: PerksContext.member_package_ids(tenant, tenant.user_id, today),
      group_ids: PerksContext.member_group_ids(tenant, tenant.user_id),
      home_location_id: membership && Map.get(membership, :home_location_id),
      joined_on: joined_on(membership && Map.get(membership, :joined_at))
    }
  end

  defp joined_on(%DateTime{} = at), do: DateTime.to_date(at)
  defp joined_on(_none), do: nil

  # -- finding -------------------------------------------------------------

  defp find_perk(context, perk_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(perk_id) do
      context
      |> client_tenants()
      |> Enum.find_value({:error, :not_found}, fn {provider, tenant} ->
        case PerksContext.get_perk(tenant, perk_id) do
          # Drafts don't exist for members; anything else answers why it can't be claimed.
          %{status: status} = perk when status != "draft" -> {:ok, provider, tenant, perk}
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
          %{user_id: user_id} = claim when user_id == tenant.user_id ->
            {:ok, provider, tenant, claim}

          _other ->
            nil
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

  defp client?(%{roles: roles}) when is_list(roles),
    do: Enum.any?(roles, &(to_string(&1) in @client_roles))

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
