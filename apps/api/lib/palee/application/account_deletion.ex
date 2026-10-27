defmodule Palee.Application.AccountDeletion do
  @moduledoc """
  ADR-211: self-service deletion of the current profile, or of the login
  with all its profiles.

  1. `request/3` needs the login's password. A verified email gets a
     confirmation link (`account_deletion`, 24 h); an unverified one
     confirms by typing the email address in the same request.
  2. Confirming (`confirm/2`, or the typed address) schedules the deletion
     `AccountDeletionPolicy.grace_days/0` days ahead: every session of the
     profiles in scope dies, signing in to them answers
     `account_deletion_scheduled`, and the security notice
     `:account_deletion_scheduled` carries the undo link
     (`account_deletion_undo`).
  3. Until then it can be undone by that link (`cancel_by_link/2`), by
     signing in with the password from the "scheduled for deletion" notice
     (`cancel_with_credentials/1`) or from another profile of the login
     (`cancel/1`).
  4. `execute_due/2` (hourly, `ExecuteAccountDeletionsJob`) carries it
     out. A profile that appears in accounting records a business must keep
     (ADR-117) is anonymised in place; every other one is deleted with what
     cascades from it. The login goes once no profile is left on it.

  A sole owner of an active business cannot delete that profile until the
  business has another owner or is closed.
  """

  require Logger

  alias Palee.Application.{LoginUser, PasswordVerifier, PublicURL, SecurityNotices}
  alias Palee.{Email, Identity}
  alias Palee.Email.LinkTokens
  alias Palee.Identity.AccountDeletionStore
  alias Palee.Identity.Domain.AccountDeletionPolicy, as: Policy

  @due_batch 50

  @doc "The login's open request as the current profile sees it."
  def status(%{login_id: login_id}) do
    case AccountDeletionStore.for_login(login_id) do
      nil -> {:ok, %{status: :none}}
      deletion -> {:ok, summary(deletion)}
    end
  end

  @doc """
  Starts a deletion. `params`: `scope` ("profile" | "login"), `password`,
  and `confirm_email` when the login's email is not verified.
  """
  def request(account, params, now \\ DateTime.utc_now()) do
    with {:ok, scope} <- Policy.scope(value(params, :scope)),
         :ok <- verify_password(account, value(params, :password)),
         profiles = Identity.list_profiles(account.login_id),
         scope = Policy.effective_scope(scope, length(profiles)),
         user_ids = Policy.profile_ids(scope, account.id, Enum.map(profiles, & &1.id)),
         :ok <- ensure_not_sole_owner(user_ids) do
      case Policy.confirmation(account) do
        :email_link -> request_link(account, scope, now)
        :typed_email -> schedule_typed(account, scope, value(params, :confirm_email), now)
      end
    end
  end

  @doc "Opens the emailed confirmation link: the deletion is scheduled."
  def confirm(raw_token, now \\ DateTime.utc_now()) do
    with {:ok, token} <- LinkTokens.consume(:account_deletion, raw_token, now),
         {:ok, deletion} <- deletion_of(token),
         {:ok, deletion} <-
           AccountDeletionStore.schedule(deletion.id, now, Policy.scheduled_for(now)) do
      # Opening a link sent to the login's address proves it is readable.
      _ =
        token.target_email &&
          Identity.mark_email_verified(token.login_id, token.target_email, now)

      :ok = after_scheduled(deletion, now)
      {:ok, summary(deletion)}
    else
      {:error, :already_scheduled} -> {:error, :invalid_deletion_link}
      {:error, :expired} -> {:error, :expired_deletion_link}
      {:error, _reason} -> {:error, :invalid_deletion_link}
    end
  end

  @doc "The undo link of the scheduled-deletion notice."
  def cancel_by_link(raw_token, now \\ DateTime.utc_now()) do
    with {:ok, token} <- LinkTokens.consume(:account_deletion_undo, raw_token, now),
         {:ok, %{status: :scheduled} = deletion} <- deletion_of(token) do
      :ok = AccountDeletionStore.delete(deletion.id)
      {:ok, %{status: :none}}
    else
      {:error, :expired} -> {:error, :expired_deletion_link}
      _invalid -> {:error, :invalid_deletion_link}
    end
  end

  @doc "Undo from a signed-in profile of the same login (also drops a request awaiting its link)."
  def cancel(%{login_id: login_id}) do
    case AccountDeletionStore.for_login(login_id) do
      nil -> {:error, :not_found}
      deletion -> AccountDeletionStore.delete(deletion.id)
    end
  end

  @doc """
  Undo from the sign-in form: the same `identifier` and `password` as a
  sign-in. Wrong credentials answer as a sign-in does; right ones cancel the
  login's scheduled deletion and sign in.
  """
  def cancel_with_credentials(params) do
    with {:ok, account} <- LoginUser.authenticate(params) do
      case AccountDeletionStore.for_login(account.login_id) do
        %{status: :scheduled} = deletion -> :ok = AccountDeletionStore.delete(deletion.id)
        _none -> :ok
      end

      LoginUser.call(params)
    end
  end

  @doc """
  `:ok`, or `{:error, {:account_deletion_scheduled, scheduled_for}}` when a
  scheduled deletion covers this profile: it cannot be opened until undone.
  """
  def ensure_open(%{login_id: login_id} = account) when is_binary(login_id) do
    case AccountDeletionStore.for_login(login_id) do
      nil ->
        :ok

      deletion ->
        if Policy.covers?(deletion, account),
          do: {:error, {:account_deletion_scheduled, deletion.scheduled_for}},
          else: :ok
    end
  end

  def ensure_open(_account), do: :ok

  @doc "Carries out the deletions whose grace is over. Returns how many ran."
  def execute_due(now \\ DateTime.utc_now(), limit \\ @due_batch) do
    now
    |> AccountDeletionStore.due(limit)
    |> Enum.count(fn deletion ->
      if Policy.due?(deletion, now), do: execute(deletion) == :ok, else: false
    end)
  end

  # -- request -----------------------------------------------------------------

  defp verify_password(%{password_hash: hash}, password)
       when is_binary(password) and is_binary(hash) do
    if PasswordVerifier.verify(password, hash), do: :ok, else: {:error, :invalid_password}
  end

  defp verify_password(_account, _password) do
    PasswordVerifier.no_user_verify()
    {:error, :invalid_password}
  end

  defp ensure_not_sole_owner(user_ids) do
    case AccountDeletionStore.sole_owned_organizations(user_ids) do
      [] -> :ok
      organizations -> {:error, {:sole_owner, Enum.map(organizations, & &1.name)}}
    end
  end

  defp request_link(account, scope, now) do
    with {:ok, deletion} <- open(account, scope, :awaiting_confirmation, nil),
         {:ok, raw, _token} <-
           LinkTokens.issue(:account_deletion, account.login_id,
             user_id: account.id,
             target_email: account.email,
             metadata: %{"deletion_id" => deletion.id},
             now: now
           ),
         {:ok, _message} <- enqueue_confirmation(account, scope, raw, deletion, now) do
      {:ok, summary(deletion)}
    else
      {:error, reason} = error ->
        # No email, no request: the person may simply try again.
        if reason != :already_scheduled, do: drop_awaiting(account.login_id)
        error
    end
  end

  defp schedule_typed(account, scope, typed, now) do
    if Policy.typed_email_matches?(typed, account.email) do
      with {:ok, deletion} <- open(account, scope, :scheduled, now) do
        :ok = after_scheduled(deletion, now)
        {:ok, summary(deletion)}
      end
    else
      {:error, :confirmation_mismatch}
    end
  end

  defp open(account, scope, status, now) do
    AccountDeletionStore.open(%{
      login_id: account.login_id,
      user_id: if(scope == :profile, do: account.id),
      scope: scope,
      status: status,
      confirmed_at: now,
      scheduled_for: now && Policy.scheduled_for(now)
    })
  end

  defp drop_awaiting(login_id) do
    case AccountDeletionStore.for_login(login_id) do
      %{status: :awaiting_confirmation} = deletion -> AccountDeletionStore.delete(deletion.id)
      _other -> :ok
    end
  end

  defp enqueue_confirmation(account, scope, raw, deletion, now) do
    Email.enqueue(
      :account_deletion_confirm,
      account.email,
      %{
        scope: scope,
        handle: account.handle,
        url: PublicURL.base_url() <> "/account-deletion/confirm#token=" <> raw,
        grace_days: Policy.grace_days()
      },
      locale: account.preferred_locale || "en",
      login_id: account.login_id,
      user_id: account.id,
      idempotency_key: "account_deletion:#{deletion.id}:confirm",
      now: now
    )
  end

  defp deletion_of(%{metadata: metadata, login_id: login_id}) do
    with id when is_binary(id) <- Map.get(metadata || %{}, "deletion_id"),
         %{login_id: ^login_id} = deletion <- AccountDeletionStore.get(id) do
      {:ok, deletion}
    else
      _missing -> {:error, :invalid}
    end
  end

  # -- scheduled ---------------------------------------------------------------

  # Sessions of every profile in scope die now; a profile deletion also stops
  # the login's email sign-in from opening the profile on its way out.
  defp after_scheduled(deletion, now) do
    profiles = Identity.list_profiles(deletion.login_id)
    in_scope = profiles_in_scope(deletion, profiles)

    Enum.each(in_scope, fn profile -> {:ok, _} = Identity.bump_security_version(profile.id) end)

    if deletion.scope == :profile do
      case Enum.find(profiles, &(&1.id != deletion.user_id)) do
        nil -> :ok
        other -> Identity.touch_last_used(deletion.login_id, other.id)
      end
    end

    notify_scheduled(deletion, List.first(in_scope), now)
  end

  defp notify_scheduled(_deletion, nil, _now), do: :ok

  defp notify_scheduled(deletion, account, now) do
    undo_url =
      case LinkTokens.issue(:account_deletion_undo, deletion.login_id,
             user_id: deletion.user_id,
             metadata: %{"deletion_id" => deletion.id},
             ttl_seconds: DateTime.diff(deletion.scheduled_for, now),
             now: now
           ) do
        {:ok, raw, _token} -> PublicURL.base_url() <> "/account-deletion/undo#token=" <> raw
        {:error, _reason} -> nil
      end

    notify(:account_deletion_scheduled, account, %{
      scope: deletion.scope,
      scheduled_for: deletion.scheduled_for,
      undo_url: undo_url
    })
  end

  defp profiles_in_scope(%{scope: :login}, profiles), do: profiles

  defp profiles_in_scope(%{scope: :profile, user_id: user_id}, profiles),
    do: Enum.filter(profiles, &(&1.id == user_id))

  # -- execution ---------------------------------------------------------------

  defp execute(deletion) do
    profiles = profiles_in_scope(deletion, Identity.list_profiles(deletion.login_id))
    user_ids = Enum.map(profiles, & &1.id)

    case AccountDeletionStore.sole_owned_organizations(user_ids) do
      [] ->
        Enum.each(profiles, &remove_profile/1)
        :ok = AccountDeletionStore.delete(deletion.id)
        :ok = AccountDeletionStore.delete_login_if_empty(deletion.login_id)

        Enum.each(profiles, fn profile ->
          notify(:account_deleted, profile, %{scope: deletion.scope, to: profile.email})
        end)

        :ok

      _owned ->
        # Became a sole owner during the grace (a co-owner left): it waits,
        # still undoable, until ownership is sorted out.
        Logger.warning("account deletion #{deletion.id} waits: sole owner of a business")
        :blocked
    end
  end

  defp remove_profile(profile) do
    if AccountDeletionStore.has_retained_records?(profile.id) do
      :ok = AccountDeletionStore.anonymize_profile(profile.id)
    else
      case Identity.delete(profile) do
        :ok -> :ok
        # Still needed elsewhere (a RESTRICT reference, the last staff
        # account): kept, but without anything that names the person.
        {:error, _reason} -> :ok = AccountDeletionStore.anonymize_profile(profile.id)
      end
    end
  end

  # SecurityNotices gains these two events in the security-notices change
  # (ADR-211 hands them over); until then there is nothing to send.
  defp notify(event, account, meta) do
    if event in SecurityNotices.events(),
      do: SecurityNotices.notify(event, account, meta),
      else: :ok
  end

  # -- shapes ------------------------------------------------------------------

  defp summary(deletion) do
    %{
      status: deletion.status,
      scope: deletion.scope,
      scheduled_for: deletion.scheduled_for
    }
  end

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
