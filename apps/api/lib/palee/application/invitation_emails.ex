defmodule Palee.Application.InvitationEmails do
  @moduledoc """
  ADR-209: a box sends its client and staff invitations by email.

    * `send/2` issues one invitation bound to the address and queues its
      `:organization_invitation` email in one transaction: if the email is
      refused (demo mode, a suppressed or invalid address, the throttle) no
      invitation is left behind. The token goes only into the email, never
      back to the inviter, so opening the link proves the inbox.
    * `bulk/2` does that for up to 200 pasted addresses, each its own
      invitation and email, within the box's and the inviter's daily caps.
    * `resend/2` re-issues an emailed invitation: the old link stops working
      and a new one is mailed, with the same roles, branches, coach, language
      and lifetime.
    * `with_delivery/1` adds each emailed invitation's address and delivery
      status (from the outbox) to the pending list.

  Telemetry: `[:palee, :invitations, :emailed]` (`%{count: n}`, metadata
  `%{organization_id, mode}` with mode `:single | :bulk | :resend`) and
  `[:palee, :invitations, :cap_reached]` (`%{count: 1}`, same metadata).
  No event carries an address.
  """

  alias Palee.Application.{OrganizationPlan, PublicURL}
  alias Palee.{Email, Facility, Identity, Organizations}
  alias Palee.Organizations.Domain.{InvitationEmailPolicy, InvitationPolicy, MembershipPolicy}
  alias Palee.Organizations.RegistrationInvitation

  @kind :organization_invitation
  @day_seconds 86_400

  @doc """
  Issues one invitation to `params["intended_email"]` and emails it. Other
  params as `IssueRegistrationInvitation`, plus `email_locale` (defaults to
  the box's language). `{:ok, %{invitation:, message:, address:}}`.
  """
  def send(context, params, now \\ DateTime.utc_now()) do
    address = value(params, :intended_email)

    with {:ok, address} <- required_address(address),
         :ok <- live(context),
         :ok <- within_caps(context, 1, :single, now),
         {:ok, sent} <- send_one(context, params, address) do
      emitted(context, 1, :single)
      {:ok, sent}
    end
  end

  @doc """
  Emails one invitation to each of `params["emails"]` (a list, or pasted
  text or CSV). `{:ok, %{results: [...], sent: n, failed: n, skipped: [...]}}`
  where a result is `%{email:, status: "queued", invitation_id:}` or
  `%{email:, error: code}`; the whole request is refused when it is too big
  or would pass a daily cap.
  """
  def bulk(context, params, now \\ DateTime.utc_now()) do
    {addresses, skipped} = InvitationEmailPolicy.parse_addresses(value(params, :emails))

    with :ok <- if(addresses == [], do: {:error, :invitation_email_required}, else: :ok),
         :ok <- live(context),
         :ok <- within_caps(context, length(addresses), :bulk, now) do
      params = Map.drop(params, [:emails, "emails", :intended_email, "intended_email"])

      results =
        Enum.map(addresses, fn address ->
          case send_one(context, params, address) do
            {:ok, %{invitation: invitation}} ->
              %{email: address, status: "queued", invitation_id: invitation.id}

            {:error, reason} ->
              %{email: address, error: error_code(reason)}
          end
        end)

      sent = Enum.count(results, &Map.has_key?(&1, :invitation_id))
      if sent > 0, do: emitted(context, sent, :bulk)

      {:ok, %{results: results, sent: sent, failed: length(results) - sent, skipped: skipped}}
    end
  end

  @doc """
  Re-issues an emailed, still pending invitation and mails the new link; the
  old one stops working. `{:ok, %{invitation:, message:, address:}}`.
  """
  def resend(context, invitation_id, now \\ DateTime.utc_now()) do
    with {:ok, old} <- Organizations.get_invitation(context, invitation_id),
         :ok <- pending(old, now),
         {:ok, address} <- emailed_address(old),
         :ok <- within_caps(context, 1, :resend, now),
         {:ok, sent} <- reissue(context, old, address, now) do
      emitted(context, 1, :resend)
      {:ok, sent}
    end
  end

  @doc """
  The pending invitations with `:email` (the address an emailed invitation
  went to, else nil) and `:delivery_status` (see
  `InvitationEmailPolicy.delivery_status/2`).
  """
  def with_delivery(invitations) do
    Enum.map(invitations, fn invitation ->
      case invitation.intended_email_encrypted do
        address when is_binary(address) and address != "" ->
          status =
            case Email.list_by_idempotency_prefix(idempotency_key(invitation)) do
              [latest | _older] -> latest.status
              [] -> nil
            end

          suppressed? = status == "sent" and Email.suppressed?(address)

          Map.merge(invitation, %{
            email: address,
            delivery_status: InvitationEmailPolicy.delivery_status(status, suppressed?)
          })

        _not_emailed ->
          Map.merge(invitation, %{email: nil, delivery_status: nil})
      end
    end)
  end

  @doc "The delivery status a freshly queued invitation email shows."
  def delivery_status(%{status: status}),
    do: InvitationEmailPolicy.delivery_status(status, false)

  # -- one invitation and its email ---------------------------------------

  defp send_one(context, params, address) do
    locale = email_locale(context, value(params, :email_locale))

    params =
      params
      |> Map.drop(["intended_email", "email_locale", "send_email"])
      |> Map.merge(%{
        intended_email: address,
        deliver_by_email: %{address: address, locale: locale}
      })

    Organizations.transaction(fn ->
      with {:ok, %{invitation: invitation, token: token}} <-
             Palee.Application.IssueRegistrationInvitation.call(context, params),
           {:ok, message} <- enqueue(context, invitation, token, address, locale) do
        {:ok, %{invitation: invitation, message: message, address: address}}
      end
    end)
  end

  defp reissue(context, old, address, now) do
    roles = RegistrationInvitation.granted_roles(old)

    Organizations.transaction(fn ->
      with {:ok, _revoked} <- Organizations.revoke_invitation(context, old.id, now),
           :ok <- OrganizationPlan.check_invitation(context, roles),
           {:ok, scope} <- current_scope(context, old),
           {:ok, %{invitation: invitation, token: token}} <-
             Organizations.issue_invitation(
               context,
               %{
                 roles: roles,
                 location_scope: scope,
                 lifetime_seconds: InvitationEmailPolicy.resend_lifetime(old),
                 intended_email: address,
                 reissue_coach_user_id: {:keep, old.coach_user_id},
                 deliver_by_email: %{address: address, locale: old.email_locale || "en"}
               },
               now
             ),
           {:ok, message} <-
             enqueue(context, invitation, token, address, old.email_locale || "en") do
        {:ok, %{invitation: invitation, message: message, address: address}}
      end
    end)
  end

  defp enqueue(context, invitation, token, address, locale) do
    settings = Organizations.get_organization_settings(context.organization_id)

    Email.enqueue(@kind, address, assigns(context, invitation, token, settings),
      locale: locale,
      organization_id: context.organization_id,
      idempotency_key: idempotency_key(invitation)
    )
  end

  defp assigns(context, invitation, token, settings) do
    roles = RegistrationInvitation.granted_roles(invitation)

    %{
      business: (settings && settings.brand_name) || context.organization.name,
      inviter: inviter_name(context.user_id),
      roles: roles,
      branches: branches(context, roles, RegistrationInvitation.granted_scope(invitation)),
      expires: expires(invitation.expires_at, settings),
      url: invitation_url(token)
    }
  end

  @doc """
  The emailed link: the redeem page `/invite`, with the token in the
  fragment so it never reaches a server log or a Referer header.
  """
  def invitation_url(token),
    do: PublicURL.base_url() <> "/invite#token=" <> URI.encode_www_form(token)

  defp idempotency_key(invitation), do: "organization_invitation:#{invitation.id}"

  # -- checks -----------------------------------------------------------------

  defp required_address(address) when is_binary(address) do
    if InvitationEmailPolicy.address?(String.trim(address)),
      do: {:ok, address |> String.trim() |> String.downcase()},
      else: {:error, :invalid_address}
  end

  defp required_address(_missing), do: {:error, :invitation_email_required}

  # ADR-184: a box in demo mode invites and emails nobody.
  defp live(context) do
    case Organizations.go_live(context, :send_outside) do
      :ok -> :ok
      {:error, _reason} -> {:error, :business_not_activated}
    end
  end

  defp within_caps(context, wanted, mode, now) do
    sent = Organizations.count_emailed_invitations(context, DateTime.add(now, -@day_seconds))

    case InvitationEmailPolicy.check(wanted, sent, limits()) do
      :ok ->
        :ok

      {:error, :invitation_email_cap_reached, _remaining} ->
        :telemetry.execute([:palee, :invitations, :cap_reached], %{count: 1}, %{
          organization_id: context.organization_id,
          mode: mode
        })

        {:error, :invitation_email_cap_reached}

      error ->
        error
    end
  end

  defp pending(invitation, now) do
    if InvitationPolicy.redeemable?(invitation, now), do: :ok, else: {:error, :invalid_invitation}
  end

  defp emailed_address(%{intended_email_encrypted: address}) when is_binary(address),
    do: {:ok, address}

  defp emailed_address(_invitation), do: {:error, :invitation_not_emailed}

  # Branches archived since the first email drop out; a staff invitation
  # left with none cannot be resent.
  defp current_scope(context, invitation) do
    case RegistrationInvitation.granted_scope(invitation) do
      :all ->
        {:ok, :all}

      ids ->
        known = context |> Facility.list_locations() |> MapSet.new(& &1.id)

        case Enum.filter(ids, &MapSet.member?(known, &1)) do
          [] -> {:error, :invalid_location_scope}
          kept -> {:ok, kept}
        end
    end
  end

  # -- the email's content ------------------------------------------------

  defp email_locale(context, requested) do
    supported = Identity.supported_locales()

    if requested in supported do
      requested
    else
      settings = Organizations.get_organization_settings(context.organization_id)
      default = settings && settings.default_locale
      if default in supported, do: default, else: "en"
    end
  end

  defp inviter_name(user_id) do
    case Identity.find_by_id(user_id) do
      %{nickname: name} when is_binary(name) -> name
      _missing -> nil
    end
  end

  defp branches(context, roles, scope) do
    if Enum.all?(roles, &(&1 in MembershipPolicy.client_roles())) do
      nil
    else
      case scope do
        :all ->
          :all

        ids ->
          context
          |> Facility.list_locations()
          |> Enum.filter(&(&1.id in ids))
          |> Enum.map(& &1.name)
      end
    end
  end

  defp expires(expires_at, settings) do
    zone = Organizations.resolve_timezone(settings)

    case DateTime.shift_zone(expires_at, zone) do
      {:ok, local} -> Calendar.strftime(local, "%d/%m/%Y %H:%M")
      _error -> Calendar.strftime(expires_at, "%d/%m/%Y %H:%M UTC")
    end
  end

  # -- plumbing ---------------------------------------------------------------

  defp emitted(context, count, mode) do
    :telemetry.execute([:palee, :invitations, :emailed], %{count: count}, %{
      organization_id: context.organization_id,
      mode: mode
    })
  end

  defp limits,
    do: InvitationEmailPolicy.limits(Application.get_env(:palee, :invitation_email_limits, []))

  defp error_code(%Ecto.Changeset{}), do: "invalid_invitation"
  defp error_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_code(_reason), do: "invalid_invitation"

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
