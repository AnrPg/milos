defmodule Palee.Application.EmailChange do
  @moduledoc """
  ADR-207: changing a login's email (shared by every profile of it) only
  once the new address proves it can receive mail.

  - `request/4` (Settings, current password): records one pending change
    and mails a 24 h link to the new address (`:email_change_confirm`).
    The old address stays the login's email, for sign-in and resets, until
    the link is opened; its inbox is told at once
    (`SecurityNotices :email_change_requested`). The answer never says
    whether the new address already has an account: the link step finds
    that out, so this form can't be used to probe addresses.
  - `confirm/2` (the link): re-checks that the address is still free, makes
    it the login's verified email and revokes every session of every
    profile. The old address gets `SecurityNotices :email_changed` with a
    7-day "this wasn't me" link.
  - `revert/2` ("this wasn't me"): puts the old address back (verified),
    revokes every session, drops any pending change and locks new changes
    for 7 days; a password reset lifts the lock.
  - `resend/2`, `cancel/1` and `status/1` serve the Settings page.

  ADR-211: a confirmed change holds the old address for this login for 7
  days (`Identity.reserve_released_email/3`), the life of the revert link.
  A request to an address held for another login answers as usual but
  records and sends nothing; confirm refuses it as `:email_unavailable`;
  a revert takes it back and ends the hold.

  Once a change or revert commits, `CorporateSeats.email_changed/3` ends the
  email-domain seats the new address no longer qualifies for.
  """

  require Logger

  alias Palee.Application.{CorporateSeats, PasswordVerifier, PublicURL, SecurityNotices}
  alias Palee.Email
  alias Palee.Email.LinkTokens
  alias Palee.Identity
  alias Palee.Identity.Domain.EmailChangePolicy
  alias Palee.Identity.EmailChangeStore

  @type status :: %{
          pending:
            nil | %{email: String.t(), requested_at: DateTime.t(), expires_at: DateTime.t()},
          locked_until: DateTime.t() | nil
        }

  @doc "The login's pending change (nil once lapsed) and any lock."
  @spec status(map(), DateTime.t()) :: status()
  def status(account, now \\ DateTime.utc_now()) do
    login = EmailChangeStore.get_login(account.login_id) || %{email_change_locked_until: nil}
    pending = EmailChangeStore.get_pending(account.login_id)

    %{
      pending:
        if(pending && not EmailChangePolicy.expired?(pending, now),
          do: %{
            email: pending.new_email,
            requested_at: pending.requested_at,
            expires_at: pending.expires_at
          }
        ),
      locked_until:
        if(EmailChangePolicy.locked?(login.email_change_locked_until, now),
          do: login.email_change_locked_until
        )
    }
  end

  @doc """
  Starts a change to `new_email`. `{:ok, status}`, or
  `{:error, :invalid_current_password | :invalid_email | :email_unchanged |
  {:email_change_locked, until} | :throttled | :suppressed | :over_budget}`.
  """
  def request(account, new_email, current_password, now \\ DateTime.utc_now()) do
    with :ok <- verify_password(account, current_password),
         {:ok, email} <- EmailChangePolicy.new_address(new_email, account.email),
         {:ok, started} <- start_unless_reserved(account, email, now) do
      SecurityNotices.notify(:email_change_requested, account, %{to: account.email})
      {:ok, request_status(started, account, email, now)}
    end
  end

  defp request_status(:reserved, account, email, now) do
    %{
      status(account, now)
      | pending: %{
          email: email,
          requested_at: now,
          expires_at: EmailChangePolicy.pending_expires_at(now)
        }
    }
  end

  defp request_status(_pending, account, _email, now), do: status(account, now)

  @doc "A fresh link (and 24 h) for the pending change; `{:error, :no_pending_email_change}` without one."
  def resend(account, now \\ DateTime.utc_now()) do
    case EmailChangeStore.get_pending(account.login_id) do
      nil ->
        {:error, :no_pending_email_change}

      pending ->
        if EmailChangePolicy.expired?(pending, now) do
          {:error, :no_pending_email_change}
        else
          with {:ok, _pending} <- start(account, pending.new_email, now),
               do: {:ok, status(account, now)}
        end
    end
  end

  @doc "Drops the pending change; its link stops working. Always `:ok`."
  def cancel(account) do
    EmailChangeStore.delete_pending(account.login_id)
  end

  # ADR-211: an address held for another login gets the answer a request
  # gets, and nothing else: no pending change, no link.
  defp start_unless_reserved(account, email, now) do
    if Identity.email_reserved_for_other?(email, account.login_id, now) do
      # A new request ends the older one's link, as `start/3` would.
      :ok = EmailChangeStore.delete_pending(account.login_id)
      {:ok, :reserved}
    else
      start(account, email, now)
    end
  end

  # One pending change per login: a new request replaces the old one, and a
  # new link replaces the older unused ones (ADR-203). The email is in the
  # same transaction, so a refused send leaves nothing pending.
  defp start(account, email, now) do
    EmailChangeStore.transaction(fn ->
      with %{} = login <- EmailChangeStore.lock_login(account.login_id) || {:error, :not_found},
           :ok <- not_locked(login, now),
           {:ok, pending} <-
             EmailChangeStore.put_pending(
               account.login_id,
               email,
               now,
               EmailChangePolicy.pending_expires_at(now)
             ),
           {:ok, raw, token} <-
             LinkTokens.issue(:email_change, account.login_id,
               user_id: account.id,
               target_email: email,
               now: now
             ),
           {:ok, _message} <-
             Email.enqueue(
               :email_change_confirm,
               email,
               %{url: link("/confirm-email-change", raw)},
               locale: Map.get(account, :preferred_locale) || "en",
               login_id: account.login_id,
               user_id: account.id,
               idempotency_key: "email_change:#{pending.id}:#{token.id}",
               now: now
             ) do
        {:ok, pending}
      end
    end)
  end

  defp not_locked(login, now) do
    if EmailChangePolicy.locked?(login.email_change_locked_until, now),
      do: {:error, {:email_change_locked, login.email_change_locked_until}},
      else: :ok
  end

  @doc """
  Opens the confirmation link. `{:ok, %{login_id, email}}`, or
  `{:error, :invalid_link | :expired_link | :email_unavailable}`.
  """
  def confirm(raw_token, now \\ DateTime.utc_now()) do
    with {:ok, token} <- consume(:email_change, raw_token, now) do
      login_id = token.login_id

      case EmailChangeStore.transaction(fn -> apply_confirm(token, now) end) do
        {:ok, %{old: old, new: new}} ->
          after_confirm(login_id, token.user_id, old, new, now)

        {:error, :email_unavailable} ->
          # Taken by another login since the request (or in a race with it).
          :ok = EmailChangeStore.delete_pending(login_id)
          {:error, :email_unavailable}

        {:error, _reason} = error ->
          error
      end
    end
  end

  defp apply_confirm(token, now) do
    login_id = token.login_id

    with %{} = login <- EmailChangeStore.lock_login(login_id) || {:error, :invalid_link},
         %{} = pending <- EmailChangeStore.get_pending(login_id) || {:error, :invalid_link},
         :ok <-
           check(
             EmailChangePolicy.same_address?(pending.new_email, token.target_email),
             :invalid_link
           ),
         :ok <- check(not EmailChangePolicy.expired?(pending, now), :expired_link),
         :ok <- address_free(pending.new_email, login_id),
         :ok <- EmailChangeStore.set_login_email(login_id, pending.new_email, now),
         :ok <- Identity.reserve_released_email(login.email, login_id, now),
         :ok <- Identity.release_reserved_email(pending.new_email, login_id) do
      {:ok, %{old: login.email, new: pending.new_email}}
    end
  end

  defp after_confirm(login_id, user_id, old, new, now) do
    follow_address(login_id, old, new)

    account = notice_account(login_id, user_id)

    revert_url =
      case LinkTokens.issue(:email_change_revert, login_id,
             user_id: account && account.id,
             target_email: old,
             metadata: %{"new_email" => new},
             now: now
           ) do
        {:ok, raw, _token} -> link("/revert-email-change", raw)
        _error -> nil
      end

    if account,
      do: SecurityNotices.notify(:email_changed, account, %{to: old, revert_url: revert_url})

    {:ok, %{login_id: login_id, email: new}}
  end

  @doc """
  "This wasn't me": `{:ok, %{email: old_address}}`, or
  `{:error, :invalid_link | :expired_link | :email_unavailable}` (the old
  address was taken by another login meanwhile).
  """
  def revert(raw_token, now \\ DateTime.utc_now()) do
    with {:ok, token} <- consume(:email_change_revert, raw_token, now) do
      old = token.target_email

      EmailChangeStore.transaction(fn ->
        with %{} = login <-
               EmailChangeStore.lock_login(token.login_id) || {:error, :invalid_link},
             :ok <- address_free(old, token.login_id),
             :ok <-
               EmailChangeStore.set_login_email(token.login_id, old, now,
                 locked_until: EmailChangePolicy.lock_until(now)
               ),
             :ok <- Identity.release_reserved_email(old, token.login_id) do
          {:ok, login.email}
        end
      end)
      |> case do
        {:ok, replaced} ->
          unless EmailChangePolicy.same_address?(replaced, old),
            do: follow_address(token.login_id, replaced, old)

          {:ok, %{email: old}}

        error ->
          error
      end
    end
  end

  # After the commit: a failure here is logged and never undoes the change.
  defp follow_address(login_id, old, new) do
    {:ok, _ended} = CorporateSeats.email_changed(login_id, old, new)
    :ok
  rescue
    error ->
      # The struct name only: a message could carry an address.
      Logger.error("email change: corporate seats not updated: #{inspect(error.__struct__)}")
      :ok
  end

  defp check(true, _reason), do: :ok
  defp check(false, reason), do: {:error, reason}

  defp address_free(email, login_id) do
    check(
      not EmailChangeStore.email_taken?(email, login_id) and
        not Identity.email_reserved_for_other?(email, login_id),
      :email_unavailable
    )
  end

  defp consume(purpose, raw_token, now) when is_binary(raw_token) do
    case LinkTokens.consume(purpose, raw_token, now) do
      {:ok, token} -> {:ok, token}
      {:error, :expired} -> {:error, :expired_link}
      {:error, _invalid_or_used} -> {:error, :invalid_link}
    end
  end

  defp consume(_purpose, _raw_token, _now), do: {:error, :invalid_link}

  # The profile the link was issued for, else any profile of the login.
  defp notice_account(login_id, user_id) do
    (user_id && Identity.find_by_id(user_id)) ||
      login_id |> Identity.list_profiles() |> List.first()
  end

  defp verify_password(account, current_password) do
    if is_binary(current_password) and current_password != "" and
         PasswordVerifier.verify(current_password, account.password_hash),
       do: :ok,
       else: {:error, :invalid_current_password}
  end

  defp link(path, raw), do: "#{PublicURL.base_url()}#{path}#token=#{raw}"
end
