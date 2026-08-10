defmodule MilosTraining.Organizations.Emails.OwnerInvitationEmail do
  @moduledoc """
  The email a vendor sends a newly-provisioned tenant's initial owner.

  The setup link is the whole point of the message, so it gets the visual
  weight; the raw token is included only as a fallback for the link not
  working (a stray character on copy/paste, an email client that mangles
  query strings) and stays secondary - present, but not something the
  reader is invited to focus on.
  """

  import Swoosh.Email

  alias MilosTraining.Application.PublicURL

  def build(%{organization_name: organization_name, to: to, token: token}) do
    setup_url = "#{PublicURL.base_url()}/set-admin?token=#{URI.encode_www_form(token)}"
    from_config = Application.fetch_env!(:milos_training, :mail_from)
    from_name = Keyword.fetch!(from_config, :name)
    from_address = Keyword.fetch!(from_config, :address)

    new()
    |> to(to)
    |> from({from_name, from_address})
    |> subject("You're set up as the owner of #{organization_name}")
    |> text_body(text_body(organization_name, setup_url, token))
    |> html_body(html_body(organization_name, setup_url, token))
  end

  defp text_body(organization_name, setup_url, token) do
    """
    You've been made the owner of #{organization_name} on #{from_product_name()}.

    To finish setting up your account and start managing #{organization_name}, open this link:

    #{setup_url}

    This link is only valid for a limited time and works once. If it's already expired, ask whoever provisioned #{organization_name} to send a fresh invitation.

    If the button or link above doesn't work, you can also enter this setup code by hand where prompted:
    #{token}

    - #{from_product_name()}
    """
  end

  defp html_body(organization_name, setup_url, token) do
    """
    <div style="font-family: -apple-system, Segoe UI, sans-serif; max-width: 480px; margin: 0 auto; color: #1a1a1a;">
      <p>You've been made the owner of <strong>#{escape(organization_name)}</strong> on #{escape(from_product_name())}.</p>
      <p>To finish setting up your account and start managing #{escape(organization_name)}, use the button below:</p>
      <p style="margin: 28px 0;">
        <a href="#{escape(setup_url)}" style="display: inline-block; padding: 12px 20px; background: #1f6f5f; color: #ffffff; text-decoration: none; border-radius: 8px; font-weight: 600;">
          Set up my account
        </a>
      </p>
      <p style="font-size: 13px; color: #555;">This link is only valid for a limited time and works once. If it's already expired, ask whoever provisioned #{escape(organization_name)} to send a fresh invitation.</p>
      <p style="margin-top: 32px; font-size: 12px; color: #888;">
        If the button doesn't work, copy this link instead:<br/>
        <a href="#{escape(setup_url)}" style="color: #888; word-break: break-all;">#{escape(setup_url)}</a>
      </p>
      <p style="margin-top: 8px; font-size: 11px; color: #aaa;">
        Setup code (only needed if the link above doesn't work): <code>#{escape(token)}</code>
      </p>
    </div>
    """
  end

  defp from_product_name,
    do: Keyword.fetch!(Application.fetch_env!(:milos_training, :mail_from), :name)

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
