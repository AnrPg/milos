defmodule Palee.Application.AssignFinanceMemberPackage do
  alias Palee.Application.UpdateFinanceMember
  alias Palee.Finance.Domain.PackageAssignmentPolicy
  alias Palee.{Finance, Identity, Organizations}

  @doc """
  `opts`: `:price_cents` sets the subscription's price instead of the
  package's (ADR-167: a season sells its package at the season's price).
  The request body can never set it.
  """
  def call(context, user_id, params, opts \\ []) do
    params =
      params
      |> Map.drop(["price_cents_snapshot", :price_cents_snapshot])
      |> put_price(opts[:price_cents])

    with user when not is_nil(user) <- Identity.find_by_id(user_id),
         :ok <- ensure_client(context, user.id),
         package_id when is_binary(package_id) <- package_id(params),
         package when not is_nil(package) <- Finance.get_package(package_id),
         :ok <- PackageAssignmentPolicy.can_assign?(package),
         {:ok, membership} <- ensure_membership(context, user.id, params) do
      Finance.assign_package(membership.id, package_id, params)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :bad_request}
    end
  end

  # ADR-217: packages are for clients only; staff never get one, not even a
  # leftover profile from before they became staff. ADR-272: a guest of the
  # box may be sold one at the desk.
  defp ensure_client(context, user_id) do
    if Organizations.buyer_role(context, user_id), do: :ok, else: {:error, :not_a_client}
  end

  # A new profile starts active: the package, not a placeholder status,
  # says what the person has (ADR-217; it used to start as "trial").
  defp ensure_membership(context, user_id, params) do
    case Finance.get_member_profile(user_id) do
      %{membership: membership} ->
        {:ok, membership}

      nil ->
        UpdateFinanceMember.call(context, user_id, %{
          "status" => "active",
          "signup_source" => signup_source(params)
        })
    end
  end

  defp put_price(params, price) when is_integer(price) and price >= 0,
    do: Map.put(params, "price_cents_snapshot", price)

  defp put_price(params, _price), do: params

  defp package_id(params),
    do: params["membership_package_id"] || params[:membership_package_id]

  defp signup_source(params),
    do: params["signup_source"] || params[:signup_source] || "admin_created"
end
