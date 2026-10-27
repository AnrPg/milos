defmodule Palee.Application.SignUpWithExistingEmail do
  @moduledoc """
  ADR-211: a public sign-up with an email that already has a login, and a
  password that is not that login's. The answer must not tell the two apart
  from a new sign-up, so nothing is created and no session is issued; the
  caller answers "we sent a link to <email>" as it does for a new account.
  The fields still get the checks a new sign-up gets (a refused handle or a
  weak password is refused here too), and the address's owner is told by
  email (`:signup_attempt_existing`), with links to sign in or reset the
  password.

  The work is close to a real sign-up's: one password hash computation (the
  verify in `RegisterProfile`), a few reads and one insert (the outbox row).
  """

  alias Palee.Application.PublicURL
  alias Palee.{Email, Identity}

  @spec call(map()) :: {:confirmation_sent, String.t()} | {:error, Ecto.Changeset.t()}
  def call(params) when is_map(params) do
    email = value(params, :email)

    with :ok <- Identity.validate_new_login(params) do
      notify_owner(email)
      {:confirmation_sent, Palee.Organizations.Domain.InvitationEmail.normalize(email)}
    end
  end

  @doc """
  A sign-up with an address held for the login that changed away from it
  (ADR-211, the ADR-207 revert window): the same answer, nothing created.
  No email: the address's inbox no longer belongs to that login's owner.
  """
  @spec reserved(map()) :: {:confirmation_sent, String.t()} | {:error, Ecto.Changeset.t()}
  def reserved(params) when is_map(params) do
    with :ok <- Identity.validate_new_login(params) do
      {:confirmation_sent,
       Palee.Organizations.Domain.InvitationEmail.normalize(value(params, :email))}
    end
  end

  defp notify_owner(email) do
    account = Identity.find_by_email(email)
    base = PublicURL.base_url()

    # A throttled, suppressed or over-budget email is dropped quietly: the
    # answer to the request must stay the same whatever the outbox says.
    _result =
      Email.enqueue(
        :signup_attempt_existing,
        email,
        %{sign_in_url: base <> "/login", reset_url: base <> "/forgot-password"},
        locale: (account && account.preferred_locale) || "en",
        login_id: account && account.login_id
      )

    :ok
  end

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
