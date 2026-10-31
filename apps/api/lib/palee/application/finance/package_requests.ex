defmodule Palee.Application.Finance.PackageRequests do
  @moduledoc """
  ADR-291: «Το θέλω». When a box takes no online payments, a person asks for
  a package in the app and pays for it at the front desk. The package waits
  as «Περιμένει πληρωμή» for 14 days, granting nothing and owing nothing,
  and shows in the desk's «Εκκρεμότητες». The desk's «Είσπραξη» records the
  money and assigns the package in one step (ADR-222/248: the receipt or
  invoice settles its first period, so no separate charge is issued).

  Prices are the ones the person was shown when asking.
  """

  alias Palee.Application.ReceiveFinancePayment
  alias Palee.Finance
  alias Palee.Finance.Domain.PackageRequestPolicy
  alias Palee.Finance.PackageRequestStore
  alias Palee.{Identity, Organizations, Payments}
  alias Palee.Payments.Domain.PackageSale

  # ── The person ──────────────────────────────────────────────────────────

  @doc """
  Asks for a package the box lists to its people. Asking again for the same
  package while one is open returns that one (`created: false`).
  """
  def request(context, package_id) do
    today = today(context)

    with {:ok, package} <- requestable_package(context, package_id),
         {:ok, request, how} <-
           scoped(context, fn ->
             PackageRequestStore.request(%{
               user_id: context.user_id,
               membership_package_id: package.id,
               package_name_snapshot: package.name,
               price_cents_snapshot: package.base_price_cents,
               currency: package.currency || "EUR",
               source: "member",
               requested_by_id: context.user_id,
               hold_until: PackageRequestPolicy.hold_until(today),
               today: today
             })
           end) do
      {:ok, %{request: present(request, today), created: how == :created}}
    end
  end

  defp requestable_package(context, package_id) do
    with {:ok, id} <- cast_id(package_id),
         %{} = package <- Finance.get_package(context, id) || {:error, :not_found},
         true <- PackageRequestPolicy.requestable?(package) || {:error, :package_not_for_sale},
         true <-
           PackageSale.listed?(package, Payments.package_offer(context)) ||
             {:error, :package_not_for_sale} do
      {:ok, package}
    end
  end

  @doc "The person's packages waiting for payment at this box."
  def mine(context) do
    today = today(context)

    scoped(context, fn ->
      today
      |> PackageRequestStore.list_open(user_id: context.user_id)
      |> Enum.map(&present(&1, today))
    end)
  end

  @doc "The person takes back a request that still waits."
  def cancel(context, request_id) do
    today = today(context)

    scoped(context, fn ->
      with %{} = request <- PackageRequestStore.get(request_id) || {:error, :not_found},
           true <- request.user_id == context.user_id || {:error, :not_found},
           true <-
             PackageRequestPolicy.open?(request, today) || {:error, :package_request_closed},
           {:ok, closed} <-
             PackageRequestStore.close(request.id, "cancelled", %{
               closed_at: DateTime.utc_now(),
               closed_by_id: context.user_id
             }) do
        {:ok, present(closed, today)}
      end
    end)
    |> closed_error()
  end

  # ── The front desk ──────────────────────────────────────────────────────

  @doc """
  The «Περιμένουν πληρωμή» queue: open requests with the person each one is
  for (display name, @handle, avatar), so the desk can open their account.
  `user_ids` narrows the queue to a branch's people (ADR-186).
  """
  def for_desk(context, opts \\ []) do
    today = today(context)

    requests =
      scoped(context, fn ->
        PackageRequestStore.list_open(today, Keyword.take(opts, [:user_ids]))
      end)

    people =
      requests
      |> Enum.map(& &1.user_id)
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1})

    Enum.map(requests, fn request ->
      request |> present(today) |> Map.put(:person, person(Map.get(people, request.user_id)))
    end)
  end

  defp person(nil), do: nil

  defp person(account),
    do: %{
      user_id: account.id,
      display_name: account.nickname,
      handle: account.handle,
      avatar_url: account.avatar_url
    }

  @doc """
  «Είσπραξη»: staff took the money at the desk. Records it (the box's
  document per ADR-222, its fiscal document per ADR-262) and assigns the
  package in the same Finance transaction, then closes the request. Safe to
  retry: the money is recorded once per request.
  """
  def collect(context, request_id, admin_id, params) do
    today = today(context)
    params = Map.new(params || %{}, fn {key, value} -> {to_string(key), value} end)

    with %{} = request <-
           scoped(context, fn -> PackageRequestStore.get(request_id) end) || {:error, :not_found},
         true <-
           PackageRequestPolicy.open?(request, today) || {:error, :package_request_closed},
         {:ok, _membership} <- ensure_membership(context, request.user_id),
         {:ok, received} <-
           Finance.with_tenant_context(context, fn ->
             ReceiveFinancePayment.call(context, request.user_id, admin_id, %{
               "purchase_package_id" => request.membership_package_id,
               "amount_cents" => request.price_cents_snapshot,
               "currency" => request.currency,
               "payment_method" => params["payment_method"],
               "notes" => params["notes"],
               "idempotency_key" => "package-request:" <> request.id
             })
           end),
         {:ok, closed} <- close_activated(context, request, received, admin_id) do
      {:ok, %{request: present(closed, today), received: received}}
    end
  end

  # A retry after the money was recorded finds the request already closed.
  defp close_activated(context, request, received, admin_id) do
    scoped(context, fn ->
      PackageRequestStore.close(request.id, "activated", %{
        closed_at: DateTime.utc_now(),
        closed_by_id: admin_id,
        membership_package_subscription_id: received[:membership_package_subscription_id],
        membership_payment_id: received.payment.id
      })
    end)
    |> case do
      {:ok, closed} ->
        {:ok, closed}

      {:error, {:package_request_closed, "activated"}} ->
        {:ok, Map.put(request, :status, "activated")}

      other ->
        other
    end
  end

  # Someone known to the box without a Finance profile yet: the profile the
  # payment needs, as a first online purchase creates it (ADR-248).
  defp ensure_membership(context, user_id) do
    case Finance.get_member_profile(context, user_id) do
      %{membership: %{} = membership} ->
        {:ok, membership}

      _none ->
        Finance.upsert_membership(context, user_id, %{
          user_type_snapshot: "member",
          status: "active",
          signup_source: "direct"
        })
    end
  end

  # ── Housekeeping ────────────────────────────────────────────────────────

  @doc "Closes as `lapsed` the requests whose 14 days ended. Returns how many."
  def lapse(context, now \\ DateTime.utc_now()) do
    today = Organizations.local_today(context.organization_id, now)
    scoped(context, fn -> PackageRequestStore.lapse_before(today, now) end)
  end

  # ── Shape ───────────────────────────────────────────────────────────────

  @doc "A request as the API shows it."
  def present(request, today) do
    %{
      id: request.id,
      user_id: request.user_id,
      package_id: request.membership_package_id,
      package_name: request.package_name_snapshot,
      price_cents: request.price_cents_snapshot,
      currency: request.currency,
      status: request.status,
      source: request.source,
      requested_at: request.inserted_at,
      hold_until: request.hold_until,
      hold_days: PackageRequestPolicy.hold_days(),
      days_left: PackageRequestPolicy.days_left(request, today)
    }
  end

  defp closed_error({:error, {:package_request_closed, _status}}),
    do: {:error, :package_request_closed}

  defp closed_error(other), do: other

  defp today(context), do: Organizations.local_today(context.organization_id)

  defp scoped(context, fun), do: PackageRequestStore.with_tenant_context(context, fun)

  defp cast_id(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp cast_id(_id), do: {:error, :not_found}
end
