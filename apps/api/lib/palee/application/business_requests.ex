defmodule Palee.Application.BusinessRequests do
  @moduledoc """
  ADR-184: requests to the platform team and the vendor console's queue.

  A person (Εγώ › Ρυθμίσεις):
  - asks to **convert** their plain account into a gym or an independent
    coach (`request_conversion/2`);
  - as the owner of a demo business, asks for it to be **activated**
    (`request_activation/2`; sign-up files one automatically);
  - withdraws a pending request (`cancel/2`).

  A vendor (`/platform/business-accounts`):
  - sees the pending requests and the businesses in demo mode with their
    owners and live links (`queue/1`);
  - **approves a conversion**: the business is created, in demo mode, owned
    by the requester, and its activation request is queued;
  - **approves an activation request**: issues the activation link for the
    requester as owner (`BusinessActivation.issue_link/4`);
  - **declines** either, with an optional note.
  """

  alias Palee.Application.{BusinessActivation, BusinessSignUp}
  alias Palee.{BusinessAccounts, Identity, Organizations}

  ## The person

  def mine(account), do: BusinessAccounts.list_my_requests(account)

  def request_conversion(account, params) do
    with {:ok, details} <- BusinessAccounts.normalize_request_details(params) do
      BusinessAccounts.file_request(account, "conversion", details)
    end
  end

  @doc "The owner of a demo business asks for it to be activated."
  def request_activation(context, params) do
    with :ok <- owner(context),
         true <- Organizations.business_gated?(context) || {:error, :business_already_active} do
      organization = context.organization

      details = %{
        business_kind: organization.provider_kind,
        business_name: organization.name,
        city: text(params, :city, 80),
        phone: text(params, :phone, 40),
        message: text(params, :message, 1000)
      }

      BusinessAccounts.file_request(context.account, "activation", details, organization.id)
    end
  end

  def cancel(account, request_id), do: BusinessAccounts.cancel_request(account, request_id)

  @doc "The latest activation request of the context's business by its signed-in owner."
  def activation_request(%{account: account, organization_id: organization_id}) do
    {:ok, requests} = BusinessAccounts.list_my_requests(account)

    requests
    |> Enum.filter(&(&1.kind == "activation" and &1.organization_id == organization_id))
    |> List.last()
  end

  def activation_request(_context), do: nil

  ## Vendors

  @doc "Pending requests and every business still in demo mode."
  def queue(platform_context) do
    with {:ok, requests} <- BusinessAccounts.list_requests(platform_context),
         {:ok, organizations} <- Organizations.list_provisioned_organizations(platform_context) do
      demo = Enum.filter(organizations, &Organizations.business_gated?/1)

      {:ok, links} =
        BusinessAccounts.list_activation_links(platform_context, Enum.map(demo, & &1.id))

      businesses = Enum.map(demo, &demo_business(platform_context, &1, links))

      user_ids =
        Enum.map(requests, & &1.user_id) ++
          Enum.map(links, & &1.user_id) ++ Enum.flat_map(businesses, & &1.owner_ids)

      {:ok, %{requests: requests, demo_businesses: businesses, accounts: accounts(user_ids)}}
    end
  end

  def decide(platform_context, request_id, params) do
    with {:ok, %{decision: decision, note: note}} <-
           BusinessAccounts.normalize_request_decision(params),
         {:ok, request} <- BusinessAccounts.get_request(platform_context, request_id),
         true <- BusinessAccounts.request_open?(request) || {:error, :business_request_closed} do
      apply_decision(platform_context, request, decision, note, params)
    end
  end

  defp apply_decision(platform_context, request, "decline", note, _params) do
    with {:ok, request} <-
           BusinessAccounts.close_request(platform_context, request, "declined", %{
             decision_note: note
           }) do
      {:ok, %{request: request}}
    end
  end

  defp apply_decision(platform_context, %{kind: "conversion"} = request, "approve", note, _params) do
    with %{} = requester <- Identity.find_by_id(request.user_id) || {:error, :account_not_found} do
      BusinessAccounts.transaction(fn ->
        with {:ok, organization} <-
               BusinessSignUp.create(requester, %{
                 business_kind: request.business_kind,
                 business_name: request.business_name,
                 city: request.city,
                 phone: request.phone,
                 message: request.message
               }),
             {:ok, request} <-
               BusinessAccounts.close_request(platform_context, request, "approved", %{
                 decision_note: note,
                 organization_id: organization.id
               }) do
          {:ok, %{request: request, organization: organization}}
        end
      end)
    end
  end

  defp apply_decision(platform_context, %{kind: "activation"} = request, "approve", _note, params) do
    with {:ok, issued} <-
           BusinessActivation.issue_link(platform_context, request.organization_id, %{
             user_id: request.user_id,
             role: Map.get(params, :role, Map.get(params, "role", "owner"))
           }) do
      {:ok, %{request: request, activation_link: issued}}
    end
  end

  defp demo_business(platform_context, organization, links) do
    owners =
      case Organizations.list_organization_memberships(platform_context, organization.id) do
        {:ok, %{memberships: memberships}} ->
          for membership <- memberships,
              membership.status == :active,
              Enum.any?(membership.roles, &(&1 in [:owner, :admin])),
              do: membership.user_id

        _error ->
          []
      end

    %{
      organization: organization,
      owner_ids: owners,
      link: Enum.find(links, &(&1.organization_id == organization.id))
    }
  end

  # Nicknames of the requesters, link holders and owners, in one read.
  defp accounts(user_ids) do
    user_ids
    |> Enum.uniq()
    |> Identity.list_by_ids()
    |> Map.new(&{&1.id, &1.nickname})
  end

  defp owner(context) do
    if Organizations.any_role?(context, [:owner]), do: :ok, else: {:error, :forbidden}
  end

  defp text(params, key, max) do
    case Map.get(params, key, Map.get(params, Atom.to_string(key))) do
      value when is_binary(value) ->
        value |> String.trim() |> String.slice(0, max) |> blank_to_nil()

      _other ->
        nil
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
