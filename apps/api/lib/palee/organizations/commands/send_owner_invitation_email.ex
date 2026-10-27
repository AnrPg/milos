defmodule Palee.Organizations.Commands.SendOwnerInvitationEmail do
  @moduledoc """
  ADR-210: the Palee team emails an issued owner (or admin) invitation's
  setup link through the outbox (`:owner_invitation`, ADR-203).

  The vendor console holds the raw token (it is shown once, at issue), so
  the request carries it; it is only used to find the invitation by its
  digest and to build the link. The email is queued, the audit event
  (`organization_invitation_emailed`) recorded and the invitation marked as
  emailed in one transaction: either all three happen or none. Answers the
  message's delivery summary (`Palee.Email.status/1`).

  One email per invitation (`owner_invitation:<invitation id>`): sending
  again returns the first message. `"resend" => true` queues another one
  (`owner_invitation:<id>:resend:<n>`), within the outbox's per-address
  throttle. A bound invitation (`intended_email_digest`) is only emailed to
  its own address.

  `locale` is the vendor's pick, else the business's default locale, else
  Greek.
  """

  alias Palee.Application.PublicURL
  alias Palee.Email
  alias Palee.Identity.Domain.Locale
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.{OrganizationStore, PlatformContext}
  alias Palee.Organizations.Domain.{InvitationEmail, InvitationPolicy, InvitationToken}

  @roles [:owner, :admin]
  @fallback_locale "el"

  def call(context, organization_id, params, now \\ DateTime.utc_now())

  def call(
        %PlatformContext{} = context,
        organization_id,
        %{"email" => email, "token" => token} = params,
        now
      )
      when is_binary(email) and is_binary(token) and email != "" and token != "" do
    with {:ok, %{invitation: invitation, organization: organization}} <-
           find(context, organization_id, token, now),
         to = InvitationEmail.normalize(email),
         :ok <- check_binding(invitation, to) do
      deliver(context, organization, invitation, token, to, params, now)
    end
  end

  def call(%PlatformContext{}, _organization_id, _params, _now), do: {:error, :invalid_email}
  def call(_context, _organization_id, _params, _now), do: {:error, :vendor_required}

  @doc "The idempotency key prefix of an invitation's emails."
  def key(invitation_id), do: "owner_invitation:#{invitation_id}"

  @doc "The delivery summaries of an invitation's emails, newest first."
  def deliveries(invitation_id), do: Email.list_by_idempotency_prefix(key(invitation_id))

  defp find(context, organization_id, token, now) do
    with {:ok, digest} <- InvitationToken.decode(token),
         %{invitation: invitation, organization: organization} = found <-
           RepoContext.run(%{user_id: context.user_id}, fn ->
             OrganizationStore.get_invitation_with_organization(digest)
           end),
         true <- organization.id == organization_id,
         true <- invitation.role in @roles,
         true <- InvitationPolicy.redeemable?(invitation, now) do
      {:ok, found}
    else
      _invalid -> {:error, :invalid_invitation}
    end
  end

  defp check_binding(%{intended_email_digest: nil}, _to), do: :ok

  defp check_binding(%{intended_email_digest: digest}, to) do
    if InvitationEmail.matches?(digest, to), do: :ok, else: {:error, :invitation_email_mismatch}
  end

  defp deliver(context, organization, invitation, token, to, params, now) do
    locale = locale(params["locale"], context, organization.id)
    assigns = %{business: organization.name, role: invitation.role, url: setup_url(token)}

    RepoContext.run(%{user_id: context.user_id}, fn ->
      OrganizationStore.transaction(fn ->
        with {:ok, message} <-
               Email.enqueue(:owner_invitation, to, assigns,
                 locale: locale,
                 organization_id: organization.id,
                 idempotency_key: idempotency_key(invitation.id, params["resend"]),
                 now: now
               ),
             {:ok, _event} <-
               OrganizationStore.record_invitation_email_sent(
                 organization.id,
                 context.user_id,
                 InvitationEmail.digest(to)
               ),
             :ok <- mark_emailed(invitation.id, now) do
          {:ok, message}
        end
      end)
    end)
    |> case do
      {:ok, message} -> Email.status(message.id)
      error -> error
    end
  end

  defp mark_emailed(invitation_id, now) do
    case Palee.Organizations.mark_invitation_emailed(invitation_id, now) do
      :ok -> :ok
      {:ok, _invitation} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp idempotency_key(invitation_id, resend) when resend in [true, "true"] do
    sent = invitation_id |> deliveries() |> length()
    "#{key(invitation_id)}:resend:#{sent}"
  end

  defp idempotency_key(invitation_id, _resend), do: key(invitation_id)

  defp locale(requested, context, organization_id) do
    with {:error, _unsupported} <- Locale.normalize(requested),
         {:error, _unsupported} <- Locale.normalize(default_locale(context, organization_id)) do
      @fallback_locale
    else
      {:ok, locale} -> locale
    end
  end

  defp default_locale(context, organization_id) do
    case RepoContext.run(%{user_id: context.user_id}, fn ->
           OrganizationStore.get_organization_settings(organization_id)
         end) do
      %{default_locale: locale} -> locale
      _none -> nil
    end
  end

  defp setup_url(token),
    do: "#{PublicURL.base_url()}/set-admin?token=#{URI.encode_www_form(token)}"
end
