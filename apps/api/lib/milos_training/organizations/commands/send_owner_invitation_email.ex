defmodule MilosTraining.Organizations.Commands.SendOwnerInvitationEmail do
  require Logger

  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Mailer
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}
  alias MilosTraining.Organizations.Domain.InvitationEmail
  alias MilosTraining.Organizations.Emails.OwnerInvitationEmail

  def call(%PlatformContext{} = context, organization_id, %{"email" => email, "token" => token})
      when is_binary(email) and is_binary(token) and email != "" and token != "" do
    # The DB lookup and the audit-event insert each need app.user_id for RLS
    # (root tenant tables), so each gets its own short-lived RepoContext.run.
    # Mailer.deliver/1 is a network call to an external provider, not DB
    # work, so it deliberately runs *outside* either wrapped block instead
    # of holding a checked-out connection for the duration of that call.
    organization =
      RepoContext.run(%{user_id: context.user_id}, fn ->
        OrganizationStore.get_organization_by_id(organization_id)
      end)

    case organization do
      nil -> {:error, :not_found}
      organization -> deliver(email, organization, token, context.user_id)
    end
  end

  def call(%PlatformContext{}, _organization_id, _params), do: {:error, :invalid_email}
  def call(_context, _organization_id, _params), do: {:error, :vendor_required}

  defp deliver(email, organization, token, platform_user_id) do
    normalized_email = InvitationEmail.normalize(email)

    built_email =
      OwnerInvitationEmail.build(%{
        organization_name: organization.name,
        to: normalized_email,
        token: token
      })

    with {:ok, _metadata} <- safe_deliver(built_email) do
      RepoContext.run(%{user_id: platform_user_id}, fn ->
        OrganizationStore.record_invitation_email_sent(
          organization.id,
          platform_user_id,
          InvitationEmail.digest(normalized_email)
        )
      end)
    end
  end

  # Swoosh's Local adapter (the config default, meant only for the dev
  # mailbox preview) talks to a GenServer that isn't started in a compiled
  # release - Mailer.deliver/1 doesn't return {:error, _} for that, it exits
  # the calling process, which without this would surface as a raw
  # unhandled-exception 500 instead of a clean error response. Any real
  # provider outage/timeout would raise the same way, so this is worth
  # having regardless of which adapter ends up configured for prod.
  defp safe_deliver(email) do
    Mailer.deliver(email)
  catch
    :exit, reason ->
      Logger.error("MilosTraining.Mailer.deliver/1 exited: #{inspect(reason)}")
      {:error, :mail_delivery_unavailable}
  end
end
