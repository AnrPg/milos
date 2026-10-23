defmodule Palee.Application.DemoSeeders.Finance do
  @moduledoc """
  ADR-184: packages, memberships, invoices and payments for the finance
  screens. Two demo packages; every mock member gets a finance membership on
  one of them, an invoice for it, and most have paid in cash. Everything is
  written through `Finance`'s scoped commands; nothing is sent.
  """

  @behaviour Palee.Application.DemoSeeder

  alias Palee.Finance

  @packages [
    %{name: "Monthly unlimited (demo)", package_type: "membership", base_price_cents: 6000},
    %{name: "10-class pack (demo)", package_type: "class_pack", base_price_cents: 9000}
  ]

  @impl true
  def section, do: "finance"

  @impl true
  def requires, do: ["members"]

  @impl true
  def sources,
    do: ["membership_packages", "memberships", "finance_invoices", "membership_payments"]

  @impl true
  def seed(context, seeded, _now) do
    people = for {"users", id} <- Map.get(seeded, "members", []), do: id

    with {:ok, packages, package_rows} <- packages(context),
         {:ok, member_rows} <- members(context, people, packages) do
      {:ok, package_rows ++ member_rows}
    end
  end

  defp packages(context) do
    Enum.reduce_while(@packages, {:ok, [], []}, fn params, {:ok, packages, rows} ->
      case Finance.create_package(context, params) do
        {:ok, package} ->
          {:cont, {:ok, packages ++ [package], rows ++ [{"membership_packages", package.id}]}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp members(context, people, packages) do
    people
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {user_id, index}, {:ok, rows} ->
      package = Enum.at(packages, rem(index, length(packages)))

      case member(context, user_id, package, rem(index, 4) != 3) do
        {:ok, member_rows} -> {:cont, {:ok, rows ++ member_rows}}
        error -> {:halt, error}
      end
    end)
  end

  defp member(context, user_id, package, paid?) do
    with {:ok, membership} <-
           Finance.upsert_membership(context, user_id, %{
             user_type_snapshot: "member",
             status: "active",
             signup_source: "admin_created"
           }),
         {:ok, subscription} <- Finance.assign_package(context, membership.id, package.id, %{}),
         {:ok, invoice} <-
           Finance.create_invoice(context, membership.id, %{
             "membership_package_subscription_id" => subscription.id
           }),
         {:ok, payment_rows} <- payment(context, membership, package, paid?) do
      {:ok,
       [{"memberships", membership.id}, {"finance_invoices", invoice.id}] ++ payment_rows}
    end
  end

  defp payment(_context, _membership, _package, false), do: {:ok, []}

  defp payment(context, membership, package, true) do
    case Finance.record_payment(context, membership.id, %{
           amount_cents: package.base_price_cents,
           payment_method: "cash",
           payment_status: "paid"
         }) do
      {:ok, payment} -> {:ok, [{"membership_payments", payment.id}]}
      error -> error
    end
  end
end
