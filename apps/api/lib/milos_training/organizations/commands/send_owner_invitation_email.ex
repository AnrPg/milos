defmodule MilosTraining.Organizations.Commands.SendOwnerInvitationEmail do
  alias MilosTraining.Mailer
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}
  alias MilosTraining.Organizations.Domain.InvitationEmail
  alias MilosTraining.Organizations.Emails.OwnerInvitationEmail

  def call(%PlatformContext{} = context, organization_id, %{"email" => email, "token" => token})
      when is_binary(email) and is_binary(token) and email != "" and token != "" do
    case OrganizationStore.get_organization_by_id(organization_id) do
      nil ->
        {:error, :not_found}

      organization ->
        email
        |> InvitationEmail.normalize()
        |> deliver(organization, token, context.user_id)
    end
  end

  def call(%PlatformContext{}, _organization_id, _params), do: {:error, :invalid_email}
  def call(_context, _organization_id, _params), do: {:error, :vendor_required}

  defp deliver(normalized_email, organization, token, platform_user_id) do
    email =
      OwnerInvitationEmail.build(%{
        organization_name: organization.name,
        to: normalized_email,
        token: token
      })

    with {:ok, _metadata} <- Mailer.deliver(email) do
      OrganizationStore.record_invitation_email_sent(
        organization.id,
        platform_user_id,
        InvitationEmail.digest(normalized_email)
      )
    end
  end
end
