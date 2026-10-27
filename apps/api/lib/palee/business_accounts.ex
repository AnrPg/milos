defmodule Palee.BusinessAccounts do
  @moduledoc """
  ADR-184: business accounts in demo mode until the platform team activates
  them.

  This context owns three things:

  - **activation links**: a vendor's one-time link for one account and one
    role of one demo business;
  - **requests** to the platform team: convert a plain account into a
    business, or activate a demo business;
  - **demo records**: the rows the demo seeders wrote, so activation deletes
    exactly those.

  Whether a business is in demo mode, and what that forbids, is the
  organization's state and is answered by `Organizations.go_live/3`
  (`Organizations.Domain.GoLivePolicy`).
  """

  alias Palee.BusinessAccounts.BusinessAccountStore
  alias Palee.BusinessAccounts.BusinessRequest

  alias Palee.BusinessAccounts.Domain.{
    ActivationLinkPolicy,
    BusinessRequestPolicy,
    DemoLifecyclePolicy
  }

  alias Palee.Organizations

  ## Activation links

  defdelegate activation_roles(), to: ActivationLinkPolicy, as: :roles
  defdelegate activation_link_state(link, now), to: ActivationLinkPolicy, as: :state

  defdelegate activation_roles_after(existing, role, kind),
    to: ActivationLinkPolicy,
    as: :roles_after

  defdelegate activation_path(token), to: ActivationLinkPolicy, as: :path

  @doc """
  A vendor issues the link of `organization_id` for `account` (its `id`, and
  the verified `email` the link is sent to). Replaces the live link of that
  business. Returns the link, the token (shown once) and the web path that
  opens it.
  """
  def issue_activation_link(
        context,
        organization_id,
        %{id: user_id} = account,
        params,
        now \\ DateTime.utc_now()
      ) do
    with {:ok, scope} <- vendor_scope(context),
         {:ok, %{role: role, lifetime_seconds: lifetime}} <-
           ActivationLinkPolicy.normalize_issue(params) do
      token = ActivationLinkPolicy.generate_token()

      attrs = %{
        organization_id: organization_id,
        user_id: user_id,
        role: role,
        token_digest: ActivationLinkPolicy.digest(token),
        expires_at: DateTime.add(now, lifetime, :second),
        created_by_id: context.user_id,
        email: Map.get(account, :email)
      }

      with {:ok, link} <- BusinessAccountStore.issue_activation_link(scope, attrs, now) do
        {:ok, %{link: link, token: token, path: ActivationLinkPolicy.path(token)}}
      end
    end
  end

  def revoke_activation_link(context, link_id, now \\ DateTime.utc_now()) do
    with {:ok, scope} <- vendor_scope(context) do
      BusinessAccountStore.revoke_activation_link(scope, link_id, now)
    end
  end

  def list_activation_links(context, organization_ids) do
    with {:ok, scope} <- vendor_scope(context) do
      {:ok, BusinessAccountStore.list_activation_links(scope, organization_ids)}
    end
  end

  @doc """
  The live link a signed-in account brings. A link for another account
  answers like an invalid one, so it reveals nothing.
  """
  def inspect_activation_link(%{id: user_id}, token, now \\ DateTime.utc_now()) do
    with {:ok, digest} <- ActivationLinkPolicy.decode(token),
         %{} = link <-
           BusinessAccountStore.get_activation_link_by_digest(%{user_id: user_id}, digest),
         true <- link.user_id == user_id,
         :live <- ActivationLinkPolicy.state(link, now) do
      {:ok, link}
    else
      _invalid -> {:error, :invalid_activation_link}
    end
  end

  @doc """
  Spends the link: the business becomes active (SECURITY DEFINER
  `palee_activate_business/2`). Runs in the caller's transaction, after the
  demo data has been deleted.
  """
  def redeem_activation_link(%{id: user_id}, token, now \\ DateTime.utc_now()) do
    with {:ok, digest} <- ActivationLinkPolicy.decode(token) do
      BusinessAccountStore.activate_business(%{user_id: user_id}, digest, now)
    end
  end

  def transaction(fun), do: BusinessAccountStore.transaction(fun)

  ## Requests to the platform team

  defdelegate normalize_request_details(params), to: BusinessRequestPolicy, as: :normalize_details

  defdelegate normalize_request_decision(params),
    to: BusinessRequestPolicy,
    as: :normalize_decision

  defdelegate signing_up?(registered_at, now), to: BusinessRequestPolicy
  defdelegate request_open?(request), to: BusinessRequestPolicy, as: :open?

  @doc "The person files a request of `kind` (conversion | activation)."
  def file_request(%{id: user_id}, kind, details, organization_id \\ nil) do
    BusinessAccountStore.create_request(
      %{user_id: user_id},
      details |> Map.merge(%{user_id: user_id, kind: kind, organization_id: organization_id})
    )
    |> case do
      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if Keyword.has_key?(errors, :user_id),
          do: {:error, :business_request_pending},
          else: {:error, changeset}

      result ->
        result
    end
  end

  def list_my_requests(%{id: user_id}),
    do: {:ok, BusinessAccountStore.list_requests(%{user_id: user_id}, %{user_id: user_id})}

  @doc "The requester withdraws their pending request."
  def cancel_request(%{id: user_id}, request_id, now \\ DateTime.utc_now()) do
    scope = %{user_id: user_id}

    case BusinessAccountStore.get_request(scope, request_id) do
      %BusinessRequest{user_id: ^user_id} = request ->
        if BusinessRequestPolicy.open?(request),
          do:
            BusinessAccountStore.update_request(
              scope,
              request,
              BusinessRequest.cancel_changeset(request, now)
            ),
          else: {:error, :business_request_closed}

      _missing ->
        {:error, :not_found}
    end
  end

  @doc "Vendors: requests, pending first by default."
  def list_requests(context, filters \\ %{status: "pending"}) do
    with {:ok, scope} <- vendor_scope(context) do
      {:ok, BusinessAccountStore.list_requests(scope, filters)}
    end
  end

  def get_request(context, request_id) do
    with {:ok, scope} <- vendor_scope(context) do
      case BusinessAccountStore.get_request(scope, request_id) do
        %BusinessRequest{} = request -> {:ok, request}
        nil -> {:error, :not_found}
      end
    end
  end

  @doc "A vendor closes a pending request (`approved` | `declined` | `completed`)."
  def close_request(
        context,
        %BusinessRequest{} = request,
        status,
        attrs,
        now \\ DateTime.utc_now()
      ) do
    with {:ok, scope} <- vendor_scope(context),
         true <- BusinessRequestPolicy.open?(request) || {:error, :business_request_closed} do
      changeset =
        BusinessRequest.decide_changeset(
          request,
          Map.merge(attrs, %{status: status, decided_by_id: context.user_id, decided_at: now})
        )

      BusinessAccountStore.update_request(scope, request, changeset)
    end
  end

  ## Demo records

  @doc "Records the rows a seeder of `section` wrote: `[{table, id}]`."
  def track_demo_records(context, section, rows),
    do: BusinessAccountStore.track_demo_records(tenant_scope(context), section, rows)

  def list_demo_records(context),
    do: BusinessAccountStore.list_demo_records(tenant_scope(context))

  @doc "Deletes the seeded rows of the tables it may touch, newest first."
  def delete_demo_rows(context, records),
    do: BusinessAccountStore.delete_demo_rows(tenant_scope(context), records)

  def clear_demo_records(context),
    do: BusinessAccountStore.clear_demo_records(tenant_scope(context))

  @doc "Whether `user_id` is one of the business's mock people."
  def demo_person?(context, user_id) when is_binary(user_id),
    do: BusinessAccountStore.demo_person?(tenant_scope(context), user_id)

  def demo_person?(_context, _user_id), do: false

  @doc "The tables a demo seeder may write (and so the wipe may delete)."
  def demo_deletable_sources, do: BusinessAccountStore.deletable_sources()

  @doc """
  Whether a notification to `user_id` (about `organization_id`, when there is
  one) must not be delivered: the recipient is a mock person, or the
  organization is a demo business and the recipient is not on its staff.
  """
  def notification_suppressed?(organization_id, user_id),
    do: BusinessAccountStore.notification_suppressed?(organization_id, user_id)

  ## Abandoned demos (`Domain.DemoLifecyclePolicy`)

  @doc "The thresholds of the abandoned-demo sweep (`config :palee, :abandoned_demos`)."
  def demo_lifecycle_thresholds,
    do: DemoLifecyclePolicy.thresholds(Application.get_env(:palee, :abandoned_demos, []))

  defdelegate demo_lifecycle_stage(candidate, now, thresholds),
    to: DemoLifecyclePolicy,
    as: :stage

  defdelegate demo_reminder_cutoff(now, thresholds), to: DemoLifecyclePolicy, as: :reminder_cutoff
  defdelegate demo_archive_cutoff(now, thresholds), to: DemoLifecyclePolicy, as: :archive_cutoff
  defdelegate demo_reminded_cutoff(now, thresholds), to: DemoLifecyclePolicy, as: :reminded_cutoff
  defdelegate demo_notice_days(thresholds), to: DemoLifecyclePolicy, as: :notice_days

  defdelegate demo_archive_on(last_active_at, thresholds),
    to: DemoLifecyclePolicy,
    as: :archive_on

  defdelegate demo_reminder_dedupe_key(organization_id, last_active_at),
    to: DemoLifecyclePolicy,
    as: :reminder_dedupe_key

  @doc """
  The owner or an admin of a demo business is active in it (a console
  request): its clock restarts and a claimed reminder is withdrawn. Free
  for active businesses and for other staff; never fails the request.
  """
  def touch_demo_activity(context, now \\ DateTime.utc_now())

  def touch_demo_activity(%{organization_id: organization_id, user_id: user_id} = context, now)
      when is_binary(organization_id) and is_binary(user_id) do
    if Organizations.business_gated?(context) and
         Organizations.any_role?(context, [:owner, :admin]) do
      touch(%{user_id: user_id}, organization_id, now)
    else
      0
    end
  end

  def touch_demo_activity(_context, _now), do: 0

  @doc "The account signed in: every demo business it runs restarts its clock."
  def touch_demo_activity_on_sign_in(user_id, now \\ DateTime.utc_now())

  def touch_demo_activity_on_sign_in(user_id, now) when is_binary(user_id),
    do: touch(%{user_id: user_id}, nil, now)

  def touch_demo_activity_on_sign_in(_user_id, _now), do: 0

  defp touch(scope, organization_id, now) do
    BusinessAccountStore.touch_demo_activity(
      scope,
      organization_id,
      now,
      demo_lifecycle_thresholds().touch_interval_seconds
    )
  rescue
    # Activity tracking must never break a request or a sign-in.
    _error in [DBConnection.ConnectionError, Postgrex.Error] -> 0
  end

  @doc "System: demo businesses idle since before `before`, with their owners."
  def idle_demo_organizations(before), do: BusinessAccountStore.idle_demo_organizations(before)

  @doc "System: claims the one-time reminder; `{:ok, last_active_at}` or `:not_claimed`."
  def claim_demo_reminder(organization_id, before, now),
    do: BusinessAccountStore.claim_demo_reminder(%{organization_id: organization_id}, before, now)

  @doc "System: archives a demo still idle and reminded long enough ago. True when it did."
  def mark_demo_archived(organization_id, before, reminded_before, now),
    do:
      BusinessAccountStore.mark_demo_archived(
        %{organization_id: organization_id},
        before,
        reminded_before,
        now
      )

  @doc "System: withdraws the pending activation request and the live link of a demo."
  def close_demo_activation(organization_id, now),
    do: BusinessAccountStore.close_demo_activation(%{organization_id: organization_id}, now)

  @doc "The account's demo businesses the sweep archived."
  def list_archived_demos(%{id: user_id}),
    do: BusinessAccountStore.list_archived_demos(%{user_id: user_id})

  @doc "The owner reopens an archived demo: active, empty, with a fresh clock."
  def reopen_demo_business(%{id: user_id}, organization_id, now \\ DateTime.utc_now()),
    do: BusinessAccountStore.reopen_demo_business(%{user_id: user_id}, organization_id, now)

  defp tenant_scope(%{organization_id: organization_id, user_id: user_id}),
    do: %{organization_id: organization_id, user_id: user_id}

  defp tenant_scope(%{organization_id: organization_id}), do: %{organization_id: organization_id}

  defp vendor_scope(%{vendor: vendor, user_id: user_id})
       when not is_nil(vendor) and is_binary(user_id),
       do: {:ok, %{user_id: user_id}}

  defp vendor_scope(_context), do: {:error, :vendor_required}
end
