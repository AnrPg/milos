defmodule Palee.Application.Payments.DeskBuyers do
  @moduledoc """
  ADR-272: the «Ποιος;» and «Τι;» steps of «Είσπραξη» on the staff phone.

  * `people/2`: who can pay. With no query, the people who checked in
    today; with one, the box's buyers (box members, athletes, guests) whose
    name or email matches, and a Palee account outside the box only when
    the query is its exact email (the person is standing at the desk; the
    directory is never browsable by name).
  * `options/2`: what a person (or a walk-in, with no person) can pay:
    open invoices, the renewal of their last πακέτο συνδρομής, the box's
    packages, shop orders waiting for payment. A free sale is always
    possible and needs nothing from here.
  * `make_guest/2`: front desk makes a found person, or a walk-in who
    gives a name and an email, a guest of the box, so they can buy a
    πακέτο συνδρομής at the desk. A new person gets a *held* profile
    (ADR-254): hidden until they prove the inbox, which claims it.
  """

  alias Palee.Application.UpdateFinanceMember
  alias Palee.{Facility, Finance, Identity, Organizations, Shop}
  alias Palee.Organizations.Domain.MembershipPolicy

  @open_invoice_statuses ~w(issued partially_paid overdue)
  @max_people 20

  # ── Ποιος; ─────────────────────────────────────────────────────────────

  def people(context, params) do
    query = params |> Map.get(:q) |> normalize_query()
    roles_by_user = roles_by_user(context)

    people =
      if query == "",
        do: checked_in_today(context, roles_by_user),
        else: matching(context, query, roles_by_user)

    {:ok, %{people: people}}
  end

  defp checked_in_today(context, roles_by_user) do
    today = Organizations.local_today(context.organization_id, DateTime.utc_now())

    context
    |> Facility.list_check_ins(%{date: today, limit: 100})
    |> Enum.reject(&is_nil(&1.user_id))
    |> Enum.uniq_by(& &1.user_id)
    |> Enum.filter(&buyer?(roles_by_user, &1.user_id))
    |> Enum.take(@max_people)
    |> Enum.map(fn check_in ->
      %{
        user_id: check_in.user_id,
        name: check_in.display_name || check_in.nickname,
        avatar_url: check_in.avatar_url,
        relation: relation(roles_by_user, check_in.user_id),
        checked_in_at: check_in.checked_in_at
      }
    end)
  end

  defp matching(_context, query, roles_by_user) do
    buyer_ids = for {id, roles} <- roles_by_user, MembershipPolicy.buyer?(roles), do: id
    folded = fold(query)

    in_box =
      buyer_ids
      |> Identity.list_by_ids()
      |> Enum.filter(&matches?(&1, folded))
      |> Enum.sort_by(&fold(&1.nickname || ""))
      |> Enum.take(@max_people)
      |> Enum.map(&person(&1, relation(roles_by_user, &1.id)))

    outside =
      if in_box == [] and email?(query), do: outside_by_email(query, roles_by_user), else: []

    in_box ++ outside
  end

  defp outside_by_email(email, roles_by_user) do
    case Identity.find_by_email(email) do
      %{id: id} = account ->
        cond do
          Identity.demo_user?(account) -> []
          Map.has_key?(roles_by_user, id) -> []
          true -> [person(account, "none")]
        end

      nil ->
        []
    end
  end

  defp person(account, relation) do
    %{
      user_id: account.id,
      name: account.nickname,
      avatar_url: account.avatar_url,
      relation: relation,
      checked_in_at: nil
    }
  end

  defp matches?(account, folded) do
    [account.nickname, account.handle, account.email]
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(&String.contains?(fold(&1), folded))
  end

  # ── Τι; ────────────────────────────────────────────────────────────────

  @doc "What `user_id` (nil: a walk-in) can pay at the desk."
  def options(context, user_id) when is_binary(user_id) do
    roles_by_user = roles_by_user(context)

    if buyer?(roles_by_user, user_id) do
      profile = Finance.get_member_profile(context, user_id)
      packages = desk_packages(context)

      {:ok,
       %{
         user_id: user_id,
         relation: relation(roles_by_user, user_id),
         invoices: open_invoices(profile),
         renewal: renewal(profile, packages),
         packages: packages,
         shop_orders: payable_orders(context, user_id)
       }}
    else
      {:error, :not_found}
    end
  end

  def options(context, nil) do
    {:ok,
     %{
       user_id: nil,
       relation: "walk_in",
       invoices: [],
       renewal: nil,
       packages: [],
       shop_orders: payable_orders(context, nil)
     }}
  end

  defp open_invoices(%{invoices: invoices}) do
    invoices
    |> Enum.filter(&(&1.status in @open_invoice_statuses and (&1.balance_due_cents || 0) > 0))
    |> Enum.map(fn invoice ->
      %{
        id: invoice.id,
        number: invoice.invoice_number,
        description: first_line(invoice),
        balance_due_cents: invoice.balance_due_cents,
        currency: invoice.currency
      }
    end)
  end

  defp open_invoices(_profile), do: []

  defp first_line(invoice) do
    case invoice[:lines] do
      [%{description: text} | _] when is_binary(text) -> text
      _none -> nil
    end
  end

  # The package of the person's latest subscription, when the box still sells it.
  defp renewal(%{package_subscriptions: [_ | _] = subscriptions}, packages) do
    latest = Enum.max_by(subscriptions, &(&1.starts_on || ~D[1970-01-01]), Date)

    case Enum.find(packages, &(&1.id == latest.membership_package_id)) do
      nil -> nil
      package -> Map.merge(package, %{ends_on: latest.ends_on})
    end
  end

  defp renewal(_profile, _packages), do: nil

  defp desk_packages(context) do
    context
    |> Finance.list_packages()
    |> Enum.filter(&(&1.active and (&1.base_price_cents || 0) > 0))
    |> Enum.sort_by(& &1.name)
    |> Enum.map(fn package ->
      %{
        id: package.id,
        name: package.name,
        price_cents: package.base_price_cents,
        currency: package.currency
      }
    end)
  end

  defp payable_orders(context, user_id) do
    filters = %{payment_statuses: [:pending_payment], limit: 50}
    filters = if user_id, do: Map.put(filters, :user_id, user_id), else: filters

    context
    |> Shop.list_orders(filters)
    |> Enum.filter(&(&1.user_id == user_id and &1.status != :cancelled))
    |> Enum.map(fn order ->
      %{
        id: order.id,
        number: order.number,
        total_cents: order.total_cents,
        currency: order.currency,
        customer_name: order.customer_name,
        summary: summary(order)
      }
    end)
  end

  defp summary(%{lines: lines}) when is_list(lines),
    do: Enum.map_join(lines, ", ", &"#{&1.product_title} ×#{&1.quantity}")

  defp summary(_order), do: ""

  # ── A guest of the box ─────────────────────────────────────────────────

  @doc """
  Makes someone a guest of the box: `user_id` (a found person) or `name`
  and `email` (a walk-in who signs up at the desk). Someone already a box
  member, athlete or guest stays as they are (`created: false`).
  """
  def make_guest(context, params) do
    with :ok <- may_make_guests(context),
         {:ok, account, new?} <- account(context, params) do
      roles = Organizations.member_roles(context.organization_id, account.id)

      cond do
        MembershipPolicy.buyer?(roles) ->
          {:ok, guest_payload(context, account, new?, false)}

        roles != [] ->
          {:error, :staff_member}

        true ->
          with {:ok, _membership} <-
                 Organizations.add_imported_membership(context, %{
                   user_id: account.id,
                   role: :guest,
                   roles: [:guest],
                   status: :active,
                   joined_at: DateTime.utc_now(),
                   invited_by_user_id: context.user_id
                 }),
               {:ok, _profile} <-
                 UpdateFinanceMember.call(context, account.id, %{
                   "status" => "active",
                   "signup_source" => "admin_created"
                 }) do
            {:ok, guest_payload(context, account, new?, true)}
          end
      end
    end
  end

  defp may_make_guests(context) do
    if MembershipPolicy.can_grant_role?(Map.get(context, :roles, []), :guest),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp account(_context, %{user_id: user_id}) when is_binary(user_id) do
    case Identity.find_by_id(user_id) do
      %{} = account -> {:ok, account, false}
      nil -> {:error, :not_found}
    end
  end

  defp account(context, %{name: name, email: email})
       when is_binary(name) and is_binary(email) do
    name = String.trim(name)
    email = email |> String.trim() |> String.downcase()

    cond do
      name == "" -> {:error, :name_required}
      not email?(email) -> {:error, :invalid_email}
      true -> existing_or_new(context, name, email)
    end
  end

  defp account(_context, _params), do: {:error, :name_required}

  # An email that already has a Palee account is that person.
  defp existing_or_new(context, name, email) do
    case Identity.find_by_email(email) do
      %{} = account ->
        {:ok, account, false}

      nil ->
        with {:ok, account} <- register(context, name, email), do: {:ok, account, true}
    end
  end

  defp guest_payload(context, account, new?, added?) do
    roles_by_user = roles_by_user(context)

    %{
      person: person(account, relation(roles_by_user, account.id)),
      created_profile: new?,
      added: added?
    }
  end

  # A walk-in who signs up at the desk: a held profile (ADR-254).
  defp register(context, name, email) do
    base =
      (Identity.suggest_handle(name) || "guest")
      |> String.slice(0, 22)
      |> String.trim(".")

    suffix = :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)

    Identity.register_held_person(context.organization_id, %{
      handle: "#{base}_#{suffix}",
      display_name: String.slice(name, 0, Identity.display_name_max_length()),
      password: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false),
      role: "member",
      email: email,
      preferred_locale: locale(context)
    })
  end

  defp locale(context) do
    settings = Organizations.get_organization_settings(context.organization_id)
    default = settings && settings.default_locale
    if default in Identity.supported_locales(), do: default, else: "en"
  end

  # ── Helpers ────────────────────────────────────────────────────────────

  defp roles_by_user(context),
    do: context |> Organizations.member_roles_by_user() |> Map.new(fn {id, m} -> {id, m.roles} end)

  defp buyer?(roles_by_user, user_id),
    do: roles_by_user |> Map.get(user_id, []) |> MembershipPolicy.buyer?()

  defp relation(roles_by_user, user_id) do
    case roles_by_user |> Map.get(user_id, []) |> MembershipPolicy.buyer_role() do
      nil -> "none"
      role -> Atom.to_string(role)
    end
  end

  defp normalize_query(query) when is_binary(query), do: query |> String.trim() |> String.slice(0, 120)
  defp normalize_query(_query), do: ""

  defp email?(text), do: Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, text)

  # Case- and accent-insensitive (Greek tonos included).
  defp fold(text) do
    text
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
  end
end
