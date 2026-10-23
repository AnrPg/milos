defmodule Palee.Application.MyTransactions do
  @moduledoc """
  Εγώ › Πληρωμές › Συναλλαγές: the person's complete money history as one
  chronological feed, newest first, with cursor pagination
  (`Finance.Domain.TransactionFeed` owns the shape, order and pages).

  Sources:

    * at every provider the person is a client of (`MyBilling.client_tenants/1`,
      each read in that provider's tenant context as the person): invoices
      with every line (packages, products or extras the box invoiced),
      payments, payment reversals (refunds, with their refund receipt when
      one was issued) and credit grants;
    * event tickets (ADR-153) and their refunds (ADR-185) from the person's
      own `community_event_attendees` rows at any host: a box, a coach, an
      organiser or a co-host that is not one of their providers. A ticket
      recorded in Finance appears once, as its payment, titled after the
      event; one without a Finance record appears from the attendee row.

  Corporate plan charges are invoiced to the company (ADR-098); a seat the
  person pays for themselves arrives as an ordinary invoice.

  Reads are bounded, never per row: one member profile and one refund
  receipt list per provider (in its own tenant context, as RLS needs), one
  attendee read for the person, one event read per event host (in that
  host's context) and one batch each for host names.
  """

  require Logger

  alias Palee.Application.{CommunityPeople, MyBilling}
  alias Palee.{Community, Finance, Organizations}
  alias Palee.Finance.Domain.TransactionFeed

  @non_draft_statuses ~w(issued partially_paid paid overdue void refunded)

  def kinds, do: TransactionFeed.kinds()

  @doc "`GET /api/me/billing/transactions`."
  def call(context, params \\ %{})

  def call(%{user_id: user_id} = context, params) when is_binary(user_id) do
    with {:ok, cursor} <- TransactionFeed.decode_cursor(param(params, :cursor)),
         {:ok, kind} <- TransactionFeed.kind_filter(param(params, :kind)) do
      clients = MyBilling.client_tenants(context)
      provider_ids = MapSet.new(clients, fn {provider, _} -> provider.organization_id end)

      {attendees, events, events_ok?} = event_facts(user_id)
      tickets = tickets_by_payment(attendees, events)

      {finance_entries, linked_payment_ids, finance_ok?} = finance_entries(clients, tickets)
      event_entries = event_entries(clients, attendees, events, linked_payment_ids)

      feed =
        TransactionFeed.page(finance_entries ++ event_entries, %{
          scope: param(params, :organization_id),
          provider_ids: provider_ids,
          kind: kind,
          cursor: cursor,
          limit: TransactionFeed.limit(param(params, :limit))
        })

      {:ok, Map.put(feed, :partial, not (finance_ok? and events_ok?))}
    end
  end

  def call(_context, _params), do: {:error, :account_required}

  defp param(params, key), do: Map.get(params, Atom.to_string(key)) || Map.get(params, key)

  # ── Finance, per provider ───────────────────────────────────────────────

  defp finance_entries(clients, tickets) do
    Enum.reduce(clients, {[], MapSet.new(), true}, fn
      {provider, {:ok, tenant}}, {entries, linked, ok?} ->
        case provider_finance(tenant, provider, tickets) do
          {:ok, more, more_linked} -> {more ++ entries, MapSet.union(linked, more_linked), ok?}
          :error -> {entries, linked, false}
        end

      _unresolved, {entries, linked, _ok?} ->
        {entries, linked, false}
    end)
  end

  defp provider_finance(tenant, provider, tickets) do
    case Finance.get_member_profile(tenant, tenant.user_id) do
      nil ->
        {:ok, [], MapSet.new()}

      profile ->
        party = counterparty(provider)
        receipts = receipts_by_reversal(tenant)

        entries =
          Enum.map(
            Enum.filter(profile.invoices, &(&1.status in @non_draft_statuses)),
            &invoice(&1, party)
          ) ++
            Enum.map(profile.payments, &payment(&1, party, tickets)) ++
            Enum.map(profile.payment_reversals || [], &refund(&1, party, receipts)) ++
            (profile.credit_ledger_entries
             |> Enum.filter(&(&1.entry_type == "grant"))
             |> Enum.map(&credit(&1, party)))

        {:ok, entries, profile.payments |> Enum.map(& &1.id) |> MapSet.new()}
    end
  rescue
    error ->
      Logger.warning(
        "transactions failed organization_id=#{provider.organization_id} error=#{inspect(error)}"
      )

      :error
  end

  defp invoice(invoice, party) do
    params = invoice.params || %{}
    receipt? = params["document_kind"] == "receipt"

    TransactionFeed.entry(
      "invoice",
      invoice.id,
      party,
      invoice.invoice_number,
      invoice.total_cents || 0,
      invoice.currency,
      invoice.status,
      invoice.issue_date || invoice.inserted_at,
      %{
        document_kind: if(receipt?, do: "receipt", else: "invoice"),
        invoice_number: invoice.invoice_number,
        due_date: invoice.due_date,
        balance_due_cents: Map.get(invoice, :balance_due_cents) || 0,
        downloadable: is_binary(params["file_key"]),
        lines:
          Enum.map(Map.get(invoice, :lines) || [], fn line ->
            %{
              description: line.description,
              line_type: line.line_type,
              quantity: line.quantity,
              unit_amount_cents: line.unit_amount_cents,
              discount_cents: line.discount_cents,
              total_cents: line.total_cents
            }
          end)
      }
    )
  end

  defp payment(payment, party, tickets) do
    event = Map.get(tickets, payment.id)

    TransactionFeed.entry(
      if(event, do: "event_payment", else: "payment"),
      payment.id,
      party,
      event && event.title,
      payment.net_amount_cents || payment.amount_cents || 0,
      payment.currency,
      payment.payment_status,
      payment.paid_on || payment.inserted_at,
      %{
        payment_method: payment.payment_method,
        finance_invoice_id: payment.finance_invoice_id,
        event_id: event && event.id
      }
    )
  end

  defp refund(reversal, party, receipts) do
    receipt = Map.get(receipts, reversal.id)

    TransactionFeed.entry(
      "refund",
      reversal.id,
      party,
      receipt && receipt.receipt_number,
      -abs(reversal.amount_cents || 0),
      reversal.currency,
      reversal.reversal_type,
      reversal.occurred_at || reversal.occurred_on,
      %{
        reason: reversal.reason,
        refund_receipt_id: receipt && receipt.id,
        receipt_number: receipt && receipt.receipt_number,
        downloadable: receipt != nil
      }
    )
  end

  defp credit(entry, party) do
    TransactionFeed.entry(
      "credit",
      entry.id,
      party,
      entry.description,
      entry.amount_cents || 0,
      entry.currency,
      entry.source_type,
      entry.occurred_at || entry.occurred_on,
      %{referral: entry.referral_reward_id != nil}
    )
  end

  defp receipts_by_reversal(tenant) do
    tenant
    |> Finance.list_refund_receipts(%{"user_id" => tenant.user_id})
    |> Map.new(&{&1.finance_payment_reversal_id, &1})
  end

  # Finance payments that record an event ticket, by payment id.
  defp tickets_by_payment(attendees, events) do
    attendees
    |> Enum.filter(& &1.finance_payment_id)
    |> Map.new(fn attendee ->
      event = Map.get(events, attendee.event_id)
      {attendee.finance_payment_id, %{id: attendee.event_id, title: event && event.title}}
    end)
  end

  # ── events at any host ──────────────────────────────────────────────────

  # The person's own attendee rows (one read, their session) and the events
  # behind them (one read per host, in that host's context).
  defp event_facts(user_id) do
    attendees =
      %{user_id: user_id}
      |> Community.attendances_of(user_id, Community.attendee_statuses())
      |> Enum.filter(&(&1.paid_at || &1.refunded_at || &1.finance_payment_id))

    {attendees, events_by_id(user_id, attendees), true}
  rescue
    error ->
      Logger.warning("event transactions failed error=#{inspect(error)}")
      {[], %{}, false}
  end

  defp events_by_id(user_id, attendees) do
    attendees
    |> Enum.group_by(& &1.organization_id, & &1.event_id)
    |> Enum.flat_map(fn {organization_id, ids} ->
      Community.list_events(%{organization_id: organization_id, user_id: user_id}, %{
        organization_ids: [organization_id],
        ids: Enum.uniq(ids),
        include_cancelled: true
      })
    end)
    |> Map.new(&{&1.id, &1})
  end

  defp event_entries(clients, attendees, events, linked_payment_ids) do
    parties = event_parties(clients, Map.values(events))

    Enum.flat_map(attendees, fn attendee ->
      event = Map.get(events, attendee.event_id)

      party =
        Map.get(parties, attendee.organization_id) || unknown_party(attendee.organization_id)

      title = event && event.title
      currency = (event && event.currency) || "EUR"

      paid =
        if attendee.paid_at && not MapSet.member?(linked_payment_ids, attendee.finance_payment_id) do
          [
            TransactionFeed.entry(
              "event_payment",
              attendee.id,
              party,
              title,
              attendee.amount_cents || (event && event.price_cents) || 0,
              currency,
              "paid",
              attendee.paid_at,
              %{payment_method: attendee.payment_method, event_id: attendee.event_id}
            )
          ]
        else
          []
        end

      refunded =
        if attendee.refunded_at do
          [
            TransactionFeed.entry(
              "event_refund",
              "refund-" <> attendee.id,
              party,
              title,
              -abs(attendee.refund_cents || 0),
              currency,
              "refunded",
              attendee.refunded_at,
              %{event_id: attendee.event_id}
            )
          ]
        else
          []
        end

      paid ++ refunded
    end)
  rescue
    error ->
      Logger.warning("event transactions failed error=#{inspect(error)}")
      []
  end

  # Who to name for each host: a provider by its name; an organiser by the
  # person who runs it (ADR-185); another box by its public page.
  defp event_parties(clients, events) do
    known =
      Map.new(clients, fn {provider, _} -> {provider.organization_id, counterparty(provider)} end)

    others =
      events
      |> Enum.map(& &1.organization_id)
      |> Enum.uniq()
      |> Enum.reject(&Map.has_key?(known, &1))

    parties_of_others(known, others, events)
  end

  defp parties_of_others(known, [], _events), do: known

  defp parties_of_others(known, others, events) do
    kinds = Organizations.provider_kinds(others)

    organisers =
      events
      |> Enum.filter(
        &(&1.organization_id in others and
            Community.organiser?(Map.get(kinds, &1.organization_id)))
      )
      |> Map.new(&{&1.organization_id, &1.created_by_id})

    people = CommunityPeople.by_ids(Map.values(organisers))

    boxes =
      others
      |> Enum.reject(&Map.has_key?(organisers, &1))
      |> Organizations.public_boxes()
      |> Map.new(&{&1.organization_id, &1})

    Enum.reduce(others, known, fn organization_id, acc ->
      party =
        case Map.fetch(organisers, organization_id) do
          {:ok, person_id} ->
            %{
              organization_id: organization_id,
              name: CommunityPeople.person(people, person_id).nickname,
              kind: "organiser",
              slug: nil
            }

          :error ->
            box = Map.get(boxes, organization_id)

            %{
              organization_id: organization_id,
              name: box && box.name,
              kind: kind_of(Map.get(kinds, organization_id)),
              slug: box && box.slug
            }
        end

      Map.put(acc, organization_id, party)
    end)
  end

  defp unknown_party(organization_id),
    do: %{organization_id: organization_id, name: nil, kind: "gym", slug: nil}

  defp counterparty(provider),
    do: %{
      organization_id: provider.organization_id,
      name: provider.name,
      kind: provider.kind,
      slug: provider.slug
    }

  defp kind_of("coach"), do: "coach"
  defp kind_of("organiser"), do: "organiser"
  defp kind_of(_gym), do: "gym"
end
