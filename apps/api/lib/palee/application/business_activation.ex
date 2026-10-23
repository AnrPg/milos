defmodule Palee.Application.BusinessActivation do
  @moduledoc """
  ADR-184: how a demo business goes live.

  1. A vendor issues an activation link for **one existing account** and a
     role (owner or admin) of the business (`issue_link/4`). A new link
     replaces the live one; the token is shown once.
  2. That account, signed in, opens `/activate-business?token=…`
     (`inspect/2`) and confirms (`redeem/3`). In one transaction:
     - the tracked demo rows are deleted (mock people first);
     - `palee_activate_business/2` makes the business active, spends the
       link, completes the pending activation request and restarts a
       creation trial from today (ADR-170);
     - the account holds the link's role (on top of the roles it had).

  What the owner set up themselves (class types, classes, packages,
  workouts, settings, the public page draft) is kept: it is real
  configuration, and only rows a seeder wrote are tracked as mock. The
  gates lift because they read the organization's activation.
  """

  alias Palee.Application.DemoData
  alias Palee.{BusinessAccounts, Identity, Organizations}

  ## Vendors

  @doc """
  Issues the link of a demo business for an account named by `user_id` or
  `nickname` (default: the business's first owner).
  """
  def issue_link(platform_context, organization_id, params, now \\ DateTime.utc_now()) do
    with {:ok, %{organization: organization, memberships: memberships}} <-
           Organizations.list_organization_memberships(platform_context, organization_id),
         :ok <- demo_business(organization),
         {:ok, user_id} <- target_account(params, memberships) do
      BusinessAccounts.issue_activation_link(
        platform_context,
        organization.id,
        user_id,
        params,
        now
      )
    end
  end

  def revoke_link(platform_context, link_id),
    do: BusinessAccounts.revoke_activation_link(platform_context, link_id)

  ## The account the link is for

  @doc "What the link would do, for the confirmation screen."
  def inspect(account, token, now \\ DateTime.utc_now()) do
    with {:ok, link} <- BusinessAccounts.inspect_activation_link(account, token, now),
         %{} = organization <- Organizations.get_by_id(link.organization_id),
         :ok <- demo_business(organization) do
      {:ok,
       %{
         link: link,
         organization: organization,
         demo: demo_summary(organization.id, account.id)
       }}
    else
      nil -> {:error, :invalid_activation_link}
      error -> error
    end
  end

  @doc "Activates the business the link names."
  def redeem(account, token, now \\ DateTime.utc_now()) do
    with {:ok, link} <- BusinessAccounts.inspect_activation_link(account, token, now),
         %{} = organization <- Organizations.get_by_id(link.organization_id),
         :ok <- demo_business(organization) do
      scope = %{organization_id: organization.id, user_id: account.id}

      BusinessAccounts.transaction(fn ->
        with {:ok, removed} <- DemoData.wipe(scope),
             {:ok, organization_id} <-
               BusinessAccounts.redeem_activation_link(account, token, now),
             roles =
               BusinessAccounts.activation_roles_after(
                 [],
                 link.role,
                 organization.provider_kind
               ),
             {:ok, membership} <-
               Organizations.grant_activation_roles(organization_id, account.id, roles, now) do
          {:ok,
           %{
             organization: Organizations.get_by_id(organization_id),
             membership: membership,
             removed: removed
           }}
        end
      end)
    else
      nil -> {:error, :invalid_activation_link}
      error -> error
    end
  end

  defp demo_business(organization) do
    if Organizations.business_gated?(organization),
      do: :ok,
      else: {:error, :business_already_active}
  end

  defp demo_summary(organization_id, user_id) do
    records = BusinessAccounts.list_demo_records(%{organization_id: organization_id, user_id: user_id})

    %{
      rows: length(records),
      people: Enum.count(records, &(&1.source == "users")),
      sections: records |> Enum.map(& &1.section) |> Enum.uniq()
    }
  end

  defp target_account(params, memberships) do
    user_id = value(params, :user_id)
    nickname = value(params, :nickname)

    cond do
      is_binary(user_id) and user_id != "" ->
        if Identity.find_by_id(user_id), do: {:ok, user_id}, else: {:error, :account_not_found}

      is_binary(nickname) and String.trim(nickname) != "" ->
        case Identity.find_by_nickname(String.trim(nickname)) do
          %{id: id} -> {:ok, id}
          _missing -> {:error, :account_not_found}
        end

      true ->
        case Enum.find(memberships, &(:owner in &1.roles and &1.status == :active)) do
          %{user_id: id} -> {:ok, id}
          nil -> {:error, :account_not_found}
        end
    end
  end

  defp value(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
