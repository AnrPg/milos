defmodule PaleeWeb.BusinessAccountJSON do
  @moduledoc "Payloads of ADR-184's business accounts, demo data and activation."

  alias Palee.BusinessAccounts

  def organization(organization) do
    %{
      id: organization.id,
      slug: organization.slug,
      name: organization.name,
      provider_kind: organization.provider_kind,
      activation: organization.activation,
      demo_started_at: organization.demo_started_at,
      activated_at: organization.activated_at
    }
  end

  def archived_demo(demo) do
    Map.take(demo, [:id, :slug, :name, :provider_kind, :demo_archived_at])
  end

  def demo_status(status, activation_request \\ nil) do
    %{
      activation: status.activation,
      gated: status.gated,
      sections: status.sections,
      activation_request: activation_request && request(activation_request)
    }
  end

  def request(request, accounts \\ %{}, verified \\ nil) do
    %{
      id: request.id,
      kind: request.kind,
      business_kind: request.business_kind,
      business_name: request.business_name,
      city: request.city,
      phone: request.phone,
      message: request.message,
      organization_id: request.organization_id,
      status: request.status,
      decision_note: request.decision_note,
      decided_at: request.decided_at,
      requested_by: Map.get(accounts, request.user_id),
      requester_email_verified: verified && MapSet.member?(verified, request.user_id),
      inserted_at: request.inserted_at
    }
  end

  def link(link, accounts \\ %{}, now \\ DateTime.utc_now(), issued \\ nil, emails \\ %{}) do
    %{
      id: link.id,
      organization_id: link.organization_id,
      user_id: link.user_id,
      nickname: Map.get(accounts, link.user_id),
      role: link.role,
      state: link |> BusinessAccounts.activation_link_state(now) |> Atom.to_string(),
      expires_at: link.expires_at,
      inserted_at: link.inserted_at,
      token: issued && issued.token,
      path: issued && issued.path,
      email_delivery:
        email_delivery((issued && Map.get(issued, :email)) || Map.get(emails, link.id))
    }
  end

  def issued_link(%{link: link} = issued), do: link(link, %{}, DateTime.utc_now(), issued)

  # ADR-205: how the link's email fared (`Palee.Email` summary), or a
  # refusal at enqueue (`not_sent` with the error code).
  defp email_delivery(nil), do: nil

  defp email_delivery(summary) do
    %{
      status: summary.status,
      error: Map.get(summary, :error),
      sent_at: Map.get(summary, :sent_at)
    }
  end

  def queue(%{requests: requests, demo_businesses: businesses, accounts: accounts} = queue) do
    now = DateTime.utc_now()
    verified = Map.get(queue, :verified, MapSet.new())
    emails = Map.get(queue, :emails, %{})

    %{
      requests: Enum.map(requests, &request(&1, accounts, verified)),
      demo_businesses:
        Enum.map(businesses, fn business ->
          %{
            organization: organization(business.organization),
            owners:
              Enum.map(
                business.owner_ids,
                &%{
                  user_id: &1,
                  nickname: Map.get(accounts, &1),
                  email_verified: MapSet.member?(verified, &1)
                }
              ),
            link: business.link && link(business.link, accounts, now, nil, emails)
          }
        end)
    }
  end

  def decision(result) do
    %{
      request: request(result.request),
      organization: Map.get(result, :organization) && organization(result.organization),
      activation_link: Map.get(result, :activation_link) && issued_link(result.activation_link)
    }
  end

  def preview(%{link: link, organization: organization, demo: demo}) do
    %{
      organization: organization(organization),
      role: link.role,
      expires_at: link.expires_at,
      demo: demo
    }
  end

  def activation(%{organization: organization, membership: membership, removed: removed}) do
    %{
      organization: organization(organization),
      roles: Enum.map(membership.roles, &to_string/1),
      removed: removed
    }
  end
end
