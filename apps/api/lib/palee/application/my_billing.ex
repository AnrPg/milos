defmodule Palee.Application.MyBilling do
  @moduledoc """
  Εγώ › Πληρωμές & αποδείξεις (vision §6.3, §7.11): one section per
  provider the person is a client of, a gym or an independent coach, with
  their packages (current one, remaining allowances, history), invoices,
  payments and outstanding balance, refund receipts, the offers they
  redeemed, the seasons they joined, their referral rewards and trials.

  Only providers where the person holds a client role (member or athlete)
  count: staff run their gym from the console. A business in demo mode
  (ADR-184) is never a provider to its members, and former providers are
  left out. Members cannot buy or cancel anything here (staff assign
  packages), so `actions` says so and the client offers «Επικοινωνία με το
  box» instead.

  Like Box ▾ (ADR-162), each provider is read in that provider's own tenant
  context as the person (their authorization there). A section that fails
  leaves its list empty and marks the provider `partial`; the rest of the
  page still shows.
  """

  require Logger

  alias Palee.Application.{EntitlementClassTypeNames, MemberPerks, MembershipRenewal, MyProviders}
  alias Palee.{Finance, Organizations, Referrals, Seasons, Trials}

  @client_roles ~w(member athlete)
  @non_draft_statuses ~w(issued partially_paid paid overdue void)
  @outstanding_statuses ~w(issued partially_paid overdue)
  @history_limit 50

  @doc "`GET /api/me/billing`: the person's billing, one section per provider."
  def call(%{user_id: user_id} = context) when is_binary(user_id) do
    clients = client_tenants(context)
    chat_slugs = clients |> Enum.map(&elem(&1, 0)) |> chat_slugs()
    trials = trials_by_provider(user_id)

    {:ok, %{providers: Enum.map(clients, &section(&1, chat_slugs, trials))}}
  end

  def call(_context), do: {:error, :account_required}

  @doc """
  The providers the person is a client of (not demo businesses), each with
  `{:ok, tenant}` in that provider's context or the error resolving it.
  `Συναλλαγές` (`MyTransactions`) reads the same set.
  """
  def client_tenants(%{user_id: user_id} = context) when is_binary(user_id) do
    {active, _former} =
      context |> Organizations.list_my_providers() |> Organizations.split_providers()

    active
    |> Enum.filter(&client?/1)
    |> Enum.map(&{&1, MyProviders.tenant_context(context, &1.organization_id)})
    |> Enum.reject(fn
      {_provider, {:ok, tenant}} -> demo?(tenant)
      _error -> false
    end)
  end

  @doc "Whether a provider row makes the person a client there (member or athlete)."
  def client?(%{roles: roles}) when is_list(roles),
    do: Enum.any?(roles, &(to_string(&1) in @client_roles))

  def client?(_provider), do: false

  @doc "ADR-184: a business in demo mode is not a real provider to its members."
  def demo?(%{organization: organization}) when is_map(organization),
    do: Map.get(organization, :activation) == "demo"

  def demo?(_tenant), do: false

  defp section({provider, resolved}, chat_slugs, trials) do
    case resolved do
      {:ok, tenant} ->
        build(tenant, provider, chat_slugs, trials)

      _error ->
        provider |> header(chat_slugs) |> Map.merge(empty_facts()) |> Map.put(:partial, true)
    end
  end

  defp build(tenant, provider, chat_slugs, trials) do
    user_id = tenant.user_id

    {finance, finance_ok?} = safe(provider, :finance, fn -> finance(tenant, user_id) end)

    {receipts, receipts_ok?} =
      safe(provider, :refund_receipts, fn -> receipts(tenant, user_id) end)

    {seasons, seasons_ok?} = safe(provider, :seasons, fn -> seasons(tenant, user_id) end)
    {invites, invites_ok?} = safe(provider, :referrals, fn -> invites(tenant, user_id) end)
    {offers, offers_ok?} = safe(provider, :available_offers, fn -> available_offers(tenant) end)
    {perks, perks_ok?} = safe(provider, :perks, fn -> MemberPerks.for_member_provider(tenant) end)

    finance = finance || empty_finance()

    provider
    |> header(chat_slugs)
    |> Map.merge(finance)
    |> Map.merge(%{
      refund_receipts: receipts || [],
      seasons: seasons || [],
      referrals: Map.merge(finance.referral_rewards, invites || empty_invites()),
      trials: Map.get(trials, provider.organization_id, []),
      available_offers: offers || [],
      perks: perks || [],
      partial:
        not (finance_ok? and receipts_ok? and seasons_ok? and invites_ok? and offers_ok? and
               perks_ok?)
    })
    |> Map.delete(:referral_rewards)
    |> put_member_actions()
  end

  # ADR-220: the member decides about renewing their current subscription and
  # can leave the box while they are not already leaving.
  defp put_member_actions(%{membership: membership, subscriptions: subscriptions} = section) do
    Map.update!(section, :actions, fn actions ->
      Map.merge(actions, %{
        self_service_cancel_auto_renew: Enum.any?(subscriptions, & &1.can_change_auto_renew),
        self_service_leave: not is_nil(membership) and is_nil(membership.leaving_on)
      })
    end)
  end

  defp header(provider, chat_slugs) do
    provider
    |> Map.take([:organization_id, :name, :slug, :kind, :logo_url, :primary_color])
    |> Map.put(:contact, %{box_chat_slug: Map.get(chat_slugs, provider.organization_id)})
    |> Map.put(:actions, %{
      self_service_purchase: false,
      self_service_cancel_auto_renew: false,
      self_service_leave: false,
      download_invoices: true
    })
    # ADR-191: the partner perks the person claimed and can still use there
    # (`build/4` fills them; a provider that fails to resolve shows none).
    |> Map.put(:perks, [])
  end

  defp empty_facts do
    empty_finance()
    |> Map.merge(%{
      refund_receipts: [],
      seasons: [],
      referrals: Map.merge(empty_rewards(), empty_invites()),
      trials: [],
      available_offers: []
    })
    |> Map.delete(:referral_rewards)
  end

  defp empty_finance do
    %{
      membership: nil,
      entitlement: nil,
      subscriptions: [],
      invoices: [],
      payments: [],
      promotions: [],
      outstanding_cents: 0,
      credit_balance_cents: 0,
      referral_rewards: empty_rewards()
    }
  end

  defp empty_rewards, do: %{credits: [], credit_total_cents: 0}
  defp empty_invites, do: %{invited: 0, trials: 0, paid: 0}

  # ── finance ────────────────────────────────────────────────────────────────

  defp finance(tenant, user_id) do
    case Finance.get_member_profile(tenant, user_id) do
      nil -> empty_finance()
      profile -> present_finance(tenant, user_id, profile)
    end
  end

  defp present_finance(tenant, user_id, profile) do
    invoices =
      profile.invoices
      |> Enum.filter(&(&1.status in @non_draft_statuses))
      |> Enum.map(&present_invoice/1)

    active_id = profile.active_package_subscription && profile.active_package_subscription.id
    credits = Enum.filter(profile.credit_ledger_entries, &(&1.referral_reward_id != nil))

    %{
      membership: present_membership(profile.membership, leave_preview(tenant, profile)),
      entitlement: entitlement(tenant, user_id),
      subscriptions:
        profile.package_subscriptions
        |> Enum.take(@history_limit)
        |> Enum.map(&present_subscription(&1, active_id)),
      invoices: Enum.take(invoices, @history_limit),
      payments: profile.payments |> Enum.take(@history_limit) |> Enum.map(&present_payment/1),
      promotions: promotions(tenant, profile.promotion_redemptions),
      outstanding_cents:
        invoices
        |> Enum.filter(&(&1.status in @outstanding_statuses))
        |> Enum.reduce(0, &(&1.balance_due_cents + &2)),
      credit_balance_cents: profile.credit_balance || 0,
      referral_rewards: %{
        credits: Enum.map(credits, &present_credit/1),
        credit_total_cents:
          credits |> Enum.map(&(&1.amount_cents || 0)) |> Enum.filter(&(&1 > 0)) |> Enum.sum()
      }
    }
  end

  defp entitlement(tenant, user_id) do
    tenant
    |> EntitlementClassTypeNames.put(Finance.get_effective_entitlement(tenant, user_id))
    |> case do
      nil -> nil
      entitlement -> Map.drop(entitlement, [:usage_entries])
    end
  end

  defp present_membership(nil, _leave_preview_on), do: nil

  defp present_membership(membership, leave_preview_on) do
    %{
      status: to_string(membership.status),
      entitlement_status: membership.entitlement_status,
      starts_on: membership.starts_on,
      expires_on: membership.expires_on,
      # ADR-220: the member is leaving (or left) on `leaving_on`; otherwise
      # `leave_preview_on` is the last day they would keep if they left now.
      leaving_on: Map.get(membership, :leaving_on),
      left_by: Map.get(membership, :left_by),
      leave_reason: Map.get(membership, :leave_reason),
      leave_preview_on: leave_preview_on
    }
  end

  defp leave_preview(_tenant, %{membership: %{leaving_on: %Date{}}}), do: nil
  defp leave_preview(tenant, _profile), do: MembershipRenewal.leave_preview(tenant)

  defp present_subscription(subscription, active_id) do
    %{
      id: subscription.id,
      status: subscription.status,
      current: subscription.id == active_id,
      package_name:
        subscription.package_name || subscription.package_code_snapshot ||
          subscription.package_family_snapshot,
      package_type: subscription.package_type,
      billing_period: subscription.billing_period_snapshot,
      price_cents: subscription.price_cents_snapshot,
      starts_on: subscription.starts_on,
      ends_on: subscription.ends_on,
      commitment_ends_on: subscription.commitment_ends_on,
      # ADR-220: the member's own choice; nil when the package does not renew
      # or the subscription is not theirs to decide (an add-on, a company seat).
      auto_renew: Map.get(subscription, :auto_renew),
      can_change_auto_renew:
        subscription.id == active_id and is_boolean(Map.get(subscription, :auto_renew)),
      corporate: subscription.corporate_client_id != nil
    }
  end

  defp present_invoice(invoice) do
    params = invoice.params || %{}

    %{
      id: invoice.id,
      invoice_number: invoice.invoice_number,
      document_kind: if(params["document_kind"] == "receipt", do: "receipt", else: "invoice"),
      status: invoice.status,
      issue_date: invoice.issue_date,
      due_date: invoice.due_date,
      total_cents: invoice.total_cents || 0,
      balance_due_cents: Map.get(invoice, :balance_due_cents) || 0,
      currency: invoice.currency || "EUR",
      downloadable: is_binary(params["file_key"])
    }
  end

  defp present_payment(payment) do
    %{
      id: payment.id,
      amount_cents: payment.amount_cents,
      net_amount_cents: payment.net_amount_cents,
      currency: payment.currency || "EUR",
      paid_on: payment.paid_on,
      payment_method: payment.payment_method,
      payment_status: payment.payment_status,
      finance_invoice_id: payment.finance_invoice_id
    }
  end

  defp present_credit(entry) do
    %{
      id: entry.id,
      amount_cents: entry.amount_cents,
      currency: entry.currency || "EUR",
      description: entry.description,
      occurred_on: entry.occurred_on
    }
  end

  defp promotions(_tenant, []), do: []

  defp promotions(tenant, redemptions) do
    names =
      tenant
      |> Finance.list_promotion_campaigns()
      |> Map.new(&{&1.id, &1.name})

    Enum.map(redemptions, fn redemption ->
      %{
        id: redemption.id,
        campaign_name: Map.get(names, redemption.promotion_campaign_id),
        discount_type: redemption.discount_type_snapshot,
        discount_value: redemption.discount_value_snapshot,
        redeemed_at: redemption.redeemed_at
      }
    end)
  end

  # Codes the box shows its members (`Finance.Domain.MemberOffers`), read
  # in two queries whatever the number of campaigns.
  defp available_offers(tenant), do: Finance.list_member_offers(tenant)

  # ── other contexts ─────────────────────────────────────────────────────────

  defp receipts(tenant, user_id) do
    tenant
    |> Finance.list_refund_receipts(%{"user_id" => user_id})
    |> Enum.filter(&(&1.user_id == user_id))
    |> Enum.take(@history_limit)
    |> Enum.map(
      &Map.take(&1, [
        :id,
        :receipt_number,
        :reversal_type,
        :amount_cents,
        :currency,
        :reason,
        :issued_at,
        :invoice_number
      ])
    )
  end

  defp seasons(tenant, user_id) do
    case Seasons.list_member_enrollments(tenant, user_id) do
      [] ->
        []

      enrollments ->
        offerings = tenant |> Seasons.list_offerings(%{}) |> Map.new(&{&1.id, &1})

        enrollments
        |> Enum.flat_map(fn enrollment ->
          case Map.get(offerings, enrollment.season_offering_id) do
            nil -> []
            offering -> [present_season(enrollment, offering)]
          end
        end)
        |> Enum.sort_by(&Date.to_gregorian_days(&1.starts_on), :desc)
    end
  end

  defp present_season(enrollment, offering) do
    %{
      id: enrollment.id,
      season_id: offering.id,
      title: offering.title,
      status: enrollment.status,
      starts_on: offering.starts_on,
      ends_on: Seasons.ends_on(offering),
      price_cents: offering.price_cents || 0,
      currency: offering.currency || "EUR"
    }
  end

  defp invites(tenant, user_id) do
    invites = Referrals.list_attributions(tenant, %{referrer_user_id: user_id, limit: 200})

    %{
      invited: length(invites),
      trials: Enum.count(invites, &(&1.trial_at || &1.event_at)),
      paid: Enum.count(invites, & &1.paid_at)
    }
  end

  defp trials_by_provider(user_id) do
    %{user_id: user_id}
    |> Trials.list_person_requests(user_id, %{})
    |> Enum.group_by(& &1.organization_id, fn request ->
      %{
        id: request.id,
        status: request.status,
        class_name: request.class_name,
        class_starts_at: request.class_starts_at
      }
    end)
  rescue
    error ->
      Logger.warning("billing trials failed error=#{inspect(error)}")
      %{}
  end

  defp chat_slugs([]), do: %{}

  defp chat_slugs(providers) do
    providers
    |> Enum.map(& &1.organization_id)
    |> Organizations.public_boxes()
    |> Map.new(&{&1.organization_id, &1.slug})
  rescue
    error ->
      Logger.warning("billing public boxes failed error=#{inspect(error)}")
      %{}
  end

  defp safe(provider, section, fun) do
    {fun.(), true}
  rescue
    error ->
      Logger.warning(
        "billing section failed section=#{section} organization_id=#{provider.organization_id} " <>
          "error=#{inspect(error)}"
      )

      {nil, false}
  end

end
