defmodule Palee.Application.MyTransactions do
  @moduledoc """
  Εγώ › Πληρωμές › Συναλλαγές: the person's complete money history as one
  chronological feed, newest first, with cursor pagination.

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

  `organization_id` narrows the feed to one provider, but always keeps the
  event entries of hosts that are not providers, so no paid event is ever
  missing. Every entry: `id`, `kind`, `counterparty`, `title`,
  `amount_cents` (negative for money back), `currency`, `status`, `date` and
  `details` for the detail sheet.
  """

  require Logger

  alias Palee.Application.{CommunityPeople, MyBilling}
  alias Palee.{Community, Finance, Organizations}

  @kinds ~w(invoice payment refund credit event_payment event_refund)
  @default_limit 30
  @max_limit 100
  @non_draft_statuses ~w(issued partially_paid paid overdue void refunded)

  def kinds, do: @kinds

  @doc "`GET /api/me/billing/transactions`."
  def call(context, params \\ %{})

  def call(%{user_id: user_id} = context, params) when is_binary(user_id) do
    with {:ok, cursor} <- decode_cursor(params["cursor"] || params[:cursor]),
         {:ok, kind} <- kind_filter(params["kind"] || params[:kind]) do
      scope = params["organization_id"] || params[:organization_id]
      limit = limit(params["limit"] || params[:limit])

      clients = MyBilling.client_tenants(context)
      provider_ids = MapSet.new(clients, fn {provider, _} -> provider.organization_id end)

      {finance_entries, linked_payment_ids, partial?} = finance_entries(clients)
      event_entries = event_entries(user_id, clients, linked_payment_ids)

      scoped =
        (finance_entries ++ event_entries)
        |> Enum.filter(&in_scope?(&1, scope, provider_ids))
        |> Enum.sort_by(&sort_key/1, :desc)

      kinds = scoped |> Enum.map(& &1.kind) |> Enum.uniq()
      filtered = if kind, do: Enum.filter(scoped, &(&1.kind == kind)), else: scoped

      page =
        filtered
        |> Enum.drop_while(&(cursor && sort_key(&1) >= cursor))
        |> Enum.take(limit + 1)

      {items, more} = Enum.split(page, limit)

      {:ok,
       %{
         transactions: Enum.map(items, &Map.delete(&1, :sort)),
         next_cursor: if(more != [], do: encode_cursor(sort_key(List.last(items)))),
         total: length(scoped),
         kinds: Enum.filter(@kinds, &(&1 in kinds)),
         partial: partial?
       }}
    end
  end

  def call(_context, _params), do: {:error, :account_required}

  defp in_scope?(_entry, nil, _provider_ids), do: true
  defp in_scope?(_entry, "", _provider_ids), do: true

  defp in_scope?(entry, organization_id, provider_ids) do
    entry.counterparty.organization_id == organization_id or
      (entry.kind in ~w(event_payment event_refund) and
         not MapSet.member?(provider_ids, entry.counterparty.organization_id))
  end

  # ── Finance, per provider ───────────────────────────────────────────────

  defp finance_entries(clients) do
    Enum.reduce(clients, {[], MapSet.new(), false}, fn
      {provider, {:ok, tenant}}, {entries, linked, partial?} ->
        case provider_finance(tenant, provider) do
          {:ok, more, more_linked} ->
            {more ++ entries, MapSet.union(linked, more_linked), partial?}

          :error ->
            {entries, linked, true}
        end

      _unresolved, {entries, linked, _partial?} ->
        {entries, linked, true}
    end)
  end

  defp provider_finance(tenant, provider) do
    case Finance.get_member_profile(tenant, tenant.user_id) do
      nil ->
        {:ok, [], MapSet.new()}

      profile ->
        party = counterparty(provider)
        tickets = event_tickets(tenant)
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

    entry(
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

    entry(
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

    entry(
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
    entry(
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

  # Finance payments that record an event ticket at this provider.
  defp event_tickets(tenant) do
    attendees =
      tenant
      |> Community.attendances_of(tenant.user_id, Community.attendee_statuses())
      |> Enum.filter(&(&1.finance_payment_id && &1.organization_id == tenant.organization_id))

    titles =
      event_titles(tenant.organization_id, tenant.user_id, Enum.map(attendees, & &1.event_id))

    Map.new(attendees, fn attendee ->
      {attendee.finance_payment_id,
       %{id: attendee.event_id, title: Map.get(titles, attendee.event_id)}}
    end)
  end

  # ── events at any host ──────────────────────────────────────────────────

  defp event_entries(user_id, clients, linked_payment_ids) do
    attendees =
      %{user_id: user_id}
      |> Community.attendances_of(user_id, Community.attendee_statuses())
      |> Enum.filter(&(&1.paid_at || &1.refunded_at))

    events = events_by_id(user_id, attendees)
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
            entry(
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
            entry(
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

  defp event_titles(_organization_id, _user_id, []), do: %{}

  defp event_titles(organization_id, user_id, ids) do
    %{organization_id: organization_id, user_id: user_id}
    |> Community.list_events(%{
      organization_ids: [organization_id],
      ids: Enum.uniq(ids),
      include_cancelled: true
    })
    |> Map.new(&{&1.id, &1.title})
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

  # ── entries, order and cursor ───────────────────────────────────────────

  defp entry(kind, source_id, party, title, amount_cents, currency, status, at, details) do
    date = to_datetime(at)

    %{
      id: "#{kind}:#{source_id}",
      kind: kind,
      source_id: source_id,
      counterparty: party,
      title: title,
      amount_cents: amount_cents,
      currency: currency || "EUR",
      status: status && to_string(status),
      date: date,
      details: details,
      sort: {date && DateTime.to_unix(date, :microsecond), "#{kind}:#{source_id}"}
    }
  end

  defp sort_key(%{sort: {nil, id}}), do: "0000000000000000000|" <> id

  defp sort_key(%{sort: {unix, id}}),
    do: (unix |> Integer.to_string() |> String.pad_leading(19, "0")) <> "|" <> id

  defp sort_key(key) when is_binary(key), do: key

  defp to_datetime(nil), do: nil
  defp to_datetime(%DateTime{} = at), do: at
  defp to_datetime(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp to_datetime(%Date{} = day), do: DateTime.new!(day, ~T[00:00:00], "Etc/UTC")

  defp encode_cursor(key), do: Base.url_encode64(key, padding: false)

  defp decode_cursor(nil), do: {:ok, nil}
  defp decode_cursor(""), do: {:ok, nil}

  defp decode_cursor(cursor) when is_binary(cursor) do
    case Base.url_decode64(cursor, padding: false) do
      {:ok, key} -> if String.contains?(key, "|"), do: {:ok, key}, else: {:error, :invalid_cursor}
      :error -> {:error, :invalid_cursor}
    end
  end

  defp decode_cursor(_cursor), do: {:error, :invalid_cursor}

  defp kind_filter(nil), do: {:ok, nil}
  defp kind_filter(""), do: {:ok, nil}
  defp kind_filter(kind) when kind in @kinds, do: {:ok, kind}
  defp kind_filter(_kind), do: {:error, :invalid_kind}

  defp limit(nil), do: @default_limit
  defp limit(value) when is_integer(value), do: value |> max(1) |> min(@max_limit)

  defp limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> limit(number)
      _other -> @default_limit
    end
  end

  defp limit(_value), do: @default_limit
end
