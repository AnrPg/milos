defmodule Palee.Application.PasswordRecovery do
  @moduledoc """
  ADR-187 and ADR-206: password recovery.

  ADR-206: a login whose email is verified gets a one-hour reset link by
  email, automatically. Everyone else, and anyone who says they can't open
  their inbox, falls back to the ADR-187 handlers below.

  A person who forgot their password asks for a reset by email or @handle;
  the answer never says whether the account exists. The request reaches the
  people who can vouch for them: the vendor, the owner, admins and front
  desk of the boxes they belong to, and their coach. The first to open it
  claims it, checks it is really them, and mails them a one-time reset link
  (24 hours) from their own mailbox. Setting the new password signs every
  profile of the login out and tells the person in-app. Recovery codes the
  person kept offline reset the password without anyone's help.

  Every step is written to the vendor's security log.
  """

  require Logger

  alias Palee.Application.{PasswordVerifier, PublicURL, SecurityNotices}
  alias Palee.Email
  alias Palee.Email.LinkTokens
  alias Palee.Identity
  alias Palee.Identity.Domain.{Locale, PasswordResetPolicy, RecoveryCodes}
  alias Palee.Identity.PasswordResetStore, as: Store
  alias Palee.Identity.RegistrationPolicy
  alias Palee.Notifications

  @log_limit 500
  @email_key "password_reset"

  # -- the person ----------------------------------------------------------

  @doc """
  ADR-206: takes a "forgot password" request from the public form and hands
  it to a background job (`request/2` does the work there). Every request
  takes the same short path and gets the same answer, so neither the
  answer nor its timing says whether the account exists, has a verified
  email or already asked.

  Options: `:cant_access_email` (the person says they can't open their
  inbox: go straight to the handlers), `:locale` (the page's language, for
  an account that never chose one), `:requester_key` (an HMAC of the
  client's IP, which caps handler requests a day).
  """
  def submit_request(identifier, opts \\ []) when is_binary(identifier) do
    args = %{
      identifier: identifier,
      cant_access_email: Keyword.get(opts, :cant_access_email, false) == true,
      locale: Keyword.get(opts, :locale),
      requester_key:
        case Keyword.get(opts, :requester_key) do
          key when is_binary(key) -> Base.url_encode64(key, padding: false)
          _none -> nil
        end
    }

    case queue().submit(args) do
      :ok -> :ok
      {:error, reason} -> Logger.error("password_reset_submit_failed #{inspect(reason)}")
    end

    :ok
  end

  @doc """
  Works out a request for the account named by `identifier` (an email or an
  @handle). Always `:ok`: whether the account exists, or already has an open
  request, is not revealed.

  ADR-206: a login whose email is verified gets a one-hour reset link by
  email (at most one every 10 minutes and five a day). An unverified email,
  a person who says they can't open their inbox (`cant_access_email: true`)
  or an email that cannot go out (suppressed address, provider budget) files
  the ADR-187 handler request instead. A request over the limits sends
  nothing and is reported as an auth anomaly.
  """
  def request(identifier, opts \\ [])

  def request(identifier, opts) when is_binary(identifier) and is_list(opts) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    case find(identifier) do
      %{} = person ->
        if Keyword.get(opts, :cant_access_email, false) or not Identity.email_verified?(person),
          do: file_handler_request(person, opts, now),
          else: email_link(person, opts, now)

      nil ->
        :ok
    end

    :ok
  end

  def request(_identifier, _opts), do: :ok

  @doc """
  What a reset link's page may show before the password is typed (ADR-206):
  `{:ok, %{expires_at: ...}}`, or `{:error, :invalid_reset_link |
  :expired_reset_link | :used_reset_link}`. Never spends the link, so a
  mail scanner or a reload cannot use it up.
  """
  def inspect_link(token, now \\ DateTime.utc_now())

  def inspect_link(token, now) when is_binary(token) do
    case LinkTokens.peek(:password_reset, token, now) do
      {:ok, link} -> {:ok, %{expires_at: link.expires_at}}
      {:error, :used} -> {:error, :used_reset_link}
      {:error, :expired} -> {:error, :expired_reset_link}
      {:error, :invalid} -> inspect_handler_link(token, now)
    end
  end

  def inspect_link(_token, _now), do: {:error, :invalid_reset_link}

  @doc """
  Sets a new password with a reset link's token: an emailed link (ADR-206)
  or one a handler mailed (ADR-187). The link is spent and the password set
  in one transaction, so neither happens without the other. The new
  password signs every profile of the login out; an emailed link also
  proves the login reads its email, and closes any open handler request.
  """
  def complete(token, password, now \\ DateTime.utc_now())

  def complete(token, password, now) when is_binary(token) and is_binary(password) do
    with {:password, true} <- {:password, RegistrationPolicy.valid_password?(password)},
         {:ok, done} <- Store.transaction(fn -> spend(token, password, now) end) do
      person =
        Identity.find_by_id(done.user_id) || %{id: done.user_id, login_id: done.login_id}

      handler = done.handler_id && Identity.find_by_id(done.handler_id)
      log(:completed, person, handler)
      notify_completed(done.user_id)
      if match?(%Identity.Account{}, person), do: notify_security(person)
      :ok
    else
      {:password, false} -> {:error, :weak_password}
      {:error, _reason} = error -> error
    end
  end

  def complete(_token, _password, _now), do: {:error, :invalid_reset_link}

  @doc """
  Resets the password with one of the login's recovery codes. A wrong code or
  an unknown account give the same answer.
  """
  def redeem_code(identifier, code, password, now \\ DateTime.utc_now()) do
    with {:password, true} <- {:password, RegistrationPolicy.valid_password?(password)},
         %{} = person <-
           (is_binary(identifier) && find(identifier)) || {:error, :invalid_recovery_code},
         :ok <- Store.use_recovery_code(person.login_id, RecoveryCodes.hash(code), now),
         :ok <- Identity.reset_login_password(person.login_id, password) do
      case Store.get_request_for_login(person.login_id) do
        nil -> :ok
        request -> Store.delete_request(request.id)
      end

      log(:recovery_code_used, person, nil)
      notify_completed(person.id)
      :ok = Palee.Application.RecoveryCodeNotices.code_used(person, now)
      :ok
    else
      {:password, false} -> {:error, :weak_password}
      {:error, :invalid} -> {:error, :invalid_recovery_code}
      {:error, :invalid_recovery_code} -> {:error, :invalid_recovery_code}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  New recovery codes for the account's login; the old ones stop working.
  Asks for the current password so a borrowed session cannot mint codes.
  """
  def generate_codes(%{login_id: login_id, password_hash: hash} = account, current_password) do
    if is_binary(current_password) and PasswordVerifier.verify(current_password, hash) do
      codes = RecoveryCodes.generate()
      :ok = Store.replace_recovery_codes(login_id, Enum.map(codes, &RecoveryCodes.hash/1))
      :ok = Palee.Application.RecoveryCodeNotices.regenerated(account)
      {:ok, codes}
    else
      {:error, :invalid_current_password}
    end
  end

  def codes_status(%{login_id: login_id}), do: Store.count_recovery_codes(login_id)

  # -- the handlers --------------------------------------------------------

  @doc "The requests `viewer` can handle, each with the state they see it in."
  def inbox(%{id: viewer_id}, now \\ DateTime.utc_now()) do
    viewer_id
    |> Store.inbox()
    |> Enum.map(&present(&1, viewer_id, now))
  end

  @doc "Opens a request: claims it for `viewer` unless someone else holds it."
  def claim(%{id: viewer_id} = viewer, request_id, now \\ DateTime.utc_now()) do
    with {:ok, entry} <- fetch_entry(viewer_id, request_id),
         {:ok, _request} <-
           Store.update_request_locked(request_id, fn request ->
             if PasswordResetPolicy.can_claim?(request, viewer_id, entry.sources, now),
               do: {:ok, claim_changes(request, viewer_id, now)},
               else: {:error, :claimed_by_other}
           end) do
      unless entry.request.claimed_by_user_id == viewer_id and
               PasswordResetPolicy.claim_active?(entry.request, now) do
        log(:claimed, entry.person, viewer)
      end

      entry(viewer_id, request_id, now)
    end
  end

  @doc "Lets go of a claim so another handler can take the request."
  def release(%{id: viewer_id} = viewer, request_id, now \\ DateTime.utc_now()) do
    with {:ok, entry} <- fetch_entry(viewer_id, request_id),
         {:ok, _request} <-
           Store.update_request_locked(request_id, fn request ->
             if request.claimed_by_user_id == viewer_id and request.status == "open",
               do: {:ok, %{claimed_by_user_id: nil, claimed_at: nil}},
               else: {:error, :not_claimed}
           end) do
      log(:released, entry.person, viewer)
      entry(viewer_id, request_id, now)
    end
  end

  @doc """
  Issues the one-time reset link. Returns the token once, with the email it
  must be sent to; the web app builds the link and the message around it.
  """
  def issue_link(%{id: viewer_id} = viewer, request_id, now \\ DateTime.utc_now()) do
    {token, hash} = PasswordResetPolicy.new_token()
    expires_at = PasswordResetPolicy.link_expires_at(now)

    with {:ok, entry} <- fetch_entry(viewer_id, request_id),
         {:ok, _request} <-
           Store.update_request_locked(request_id, fn request ->
             if PasswordResetPolicy.can_claim?(request, viewer_id, entry.sources, now) do
               {:ok,
                %{
                  status: "link_issued",
                  claimed_by_user_id: viewer_id,
                  claimed_at: now,
                  link_token_hash: hash,
                  link_expires_at: expires_at,
                  link_issued_by_user_id: viewer_id,
                  link_issued_at: now
                }}
             else
               {:error, :claimed_by_other}
             end
           end) do
      log(:link_issued, entry.person, viewer)

      {:ok,
       %{
         token: token,
         email: entry.person.email,
         expires_at: expires_at,
         request: present(%{entry | request: Store.get_request(request_id)}, viewer_id, now)
       }}
    end
  end

  @doc """
  Closes a request without a reset: `:rejected` when the handler could not
  confirm it was really the person, `:dismissed` to clear an expired one.
  Either way it leaves every list.
  """
  def close(%{id: viewer_id} = viewer, request_id, outcome, now \\ DateTime.utc_now())
      when outcome in [:rejected, :dismissed] do
    with {:ok, entry} <- fetch_entry(viewer_id, request_id),
         true <-
           PasswordResetPolicy.can_claim?(entry.request, viewer_id, entry.sources, now) ||
             {:error, :claimed_by_other} do
      :ok = Store.delete_request(request_id)
      log(outcome, entry.person, viewer)
      :ok
    end
  end

  @doc "Hides a request from the viewer's own list, for good."
  def hide(%{id: viewer_id}, request_id) do
    with {:ok, _entry} <- fetch_entry(viewer_id, request_id) do
      Store.hide(request_id, viewer_id)
    end
  end

  @doc "The security log (vendor only; the router enforces it)."
  def log_entries, do: Store.list_log(@log_limit)

  # -- helpers -------------------------------------------------------------

  defp email_link(person, opts, now) do
    if PasswordResetPolicy.email_allowed?(emails_sent(person.login_id), now) do
      case Store.transaction(fn -> issue_and_enqueue(person, opts, now) end) do
        {:ok, _message} -> log(:link_emailed, person, nil)
        {:error, :throttled} -> throttled(person, "password_reset_throttled")
        # The address bounced, the provider's budget is spent, ...: people
        # who know the person can still help.
        {:error, _reason} -> file_handler_request(person, opts, now)
      end
    else
      throttled(person, "password_reset_throttled")
    end
  end

  # Issuing the link replaces the login's older unused one, so it happens
  # only together with the email that carries the new one.
  defp issue_and_enqueue(person, opts, now) do
    with {:ok, raw, link} <-
           LinkTokens.issue(:password_reset, person.login_id,
             user_id: person.id,
             target_email: person.email,
             ttl_seconds: PasswordResetPolicy.email_link_ttl_seconds(),
             now: now
           ) do
      Email.enqueue(
        :password_reset,
        person.email,
        %{url: reset_url(raw), name: person.nickname},
        locale: email_locale(person, opts),
        login_id: person.login_id,
        user_id: person.id,
        category: :security,
        idempotency_key: "#{@email_key}:#{person.login_id}:#{link.id}",
        now: now
      )
    end
  end

  defp emails_sent(login_id) do
    "#{@email_key}:#{login_id}:"
    |> Email.list_by_idempotency_prefix()
    |> Enum.reject(&(&1.status in ["failed", "suppressed"]))
    |> Enum.map(&to_utc(&1.inserted_at))
  end

  defp to_utc(%DateTime{} = at), do: at
  defp to_utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")

  defp reset_url(raw), do: PublicURL.base_url() <> "/reset-password#token=" <> raw

  defp email_locale(person, opts) do
    [person.preferred_locale, Keyword.get(opts, :locale)]
    |> Enum.find_value(Locale.default(), fn locale ->
      case Locale.normalize(locale) do
        {:ok, supported} -> supported
        {:error, _unsupported} -> nil
      end
    end)
  end

  defp file_handler_request(person, opts, now) do
    key = Keyword.get(opts, :requester_key)

    cond do
      Store.get_request_for_login(person.login_id) ->
        :ok

      is_binary(key) and
          not PasswordResetPolicy.handler_request_allowed?(
            Store.count_requests_from(key, PasswordResetPolicy.window_start(now))
          ) ->
        throttled(person, "password_reset_handler_cap")

      true ->
        with {:ok, request} <-
               Store.create_request(%{
                 login_id: person.login_id,
                 user_id: person.id,
                 requester_key: key
               }) do
          log(:requested, person, nil)
          notify_handlers(request, person, now)
        end
    end
  end

  defp throttled(person, reason) do
    :telemetry.execute([:palee, :auth, :anomaly], %{count: 1}, %{reason: reason})
    log(:throttled, person, nil)
  end

  defp spend(token, password, now) do
    case LinkTokens.consume(:password_reset, token, now) do
      {:ok, link} ->
        with :ok <- verify_address(link, now),
             :ok <- Identity.reset_login_password(link.login_id, password) do
          case Store.get_request_for_login(link.login_id) do
            nil -> :ok
            request -> Store.delete_request(request.id)
          end

          {:ok, %{login_id: link.login_id, user_id: link.user_id, handler_id: nil}}
        end

      {:error, :used} ->
        {:error, :used_reset_link}

      {:error, :expired} ->
        {:error, :expired_reset_link}

      {:error, :invalid} ->
        spend_handler_link(token, password, now)
    end
  end

  # The link went to the login's address when it was sent; after an email
  # change it no longer proves anything and stops working.
  defp verify_address(%{target_email: email} = link, now) when is_binary(email) do
    case Identity.mark_email_verified(link.login_id, email, now) do
      :ok -> :ok
      {:error, _mismatch} -> {:error, :invalid_reset_link}
    end
  end

  defp verify_address(_link, _now), do: {:error, :invalid_reset_link}

  defp spend_handler_link(token, password, now) do
    case Store.lock_request_by_token_hash(PasswordResetPolicy.hash_token(token)) do
      nil ->
        {:error, :invalid_reset_link}

      request ->
        cond do
          PasswordResetPolicy.expired?(request, now) ->
            {:error, :expired_reset_link}

          (result = Identity.reset_login_password(request.login_id, password)) != :ok ->
            result

          true ->
            :ok = Store.delete_request(request.id)

            {:ok,
             %{
               login_id: request.login_id,
               user_id: request.user_id,
               handler_id: request.link_issued_by_user_id
             }}
        end
    end
  end

  defp inspect_handler_link(token, now) do
    case Store.get_request_by_token_hash(PasswordResetPolicy.hash_token(token)) do
      nil ->
        {:error, :invalid_reset_link}

      request ->
        if PasswordResetPolicy.expired?(request, now),
          do: {:error, :expired_reset_link},
          else: {:ok, %{expires_at: request.link_expires_at}}
    end
  end

  defp notify_security(account) do
    SecurityNotices.notify(:password_reset_completed, account, %{})
  rescue
    error -> Logger.error("password reset notice failed: #{Exception.message(error)}")
  end

  defp queue, do: Application.fetch_env!(:palee, :password_reset_queue)

  defp find(identifier) do
    identifier = String.trim(identifier)

    cond do
      identifier == "" ->
        nil

      String.contains?(identifier, "@") and not String.starts_with?(identifier, "@") ->
        Identity.find_by_email(identifier)

      true ->
        Identity.find_by_handle(identifier)
    end
  end

  defp fetch_entry(viewer_id, request_id) do
    case Ecto.UUID.cast(request_id) do
      {:ok, id} ->
        case Store.inbox_entry(viewer_id, id) do
          nil -> {:error, :not_found}
          entry -> {:ok, entry}
        end

      :error ->
        {:error, :not_found}
    end
  end

  defp entry(viewer_id, request_id, now) do
    case Store.inbox_entry(viewer_id, request_id) do
      nil -> {:error, :not_found}
      entry -> {:ok, present(entry, viewer_id, now)}
    end
  end

  defp claim_changes(request, viewer_id, now) do
    changes = %{claimed_by_user_id: viewer_id, claimed_at: now}

    if PasswordResetPolicy.expired?(request, now),
      do: Map.merge(changes, %{status: "open", link_token_hash: nil, link_expires_at: nil}),
      else: changes
  end

  defp present(entry, viewer_id, now) do
    request = entry.request

    %{
      id: request.id,
      state: PasswordResetPolicy.state(request, viewer_id, now),
      person: entry.person,
      claimed_by:
        if(PasswordResetPolicy.claim_active?(request, now) or request.status == "link_issued",
          do: entry.claimer
        ),
      sources: entry.sources,
      organizations: entry.organizations,
      requested_at: request.inserted_at,
      link_issued_at: request.link_issued_at,
      link_expires_at: request.link_expires_at
    }
  end

  defp notify_handlers(request, person, _now) do
    payload = %{
      request_id: request.id,
      person_handle: person.handle,
      person_name: person.nickname,
      dedupe_key: "password_reset_requested:#{request.id}"
    }

    request.login_id
    |> Store.handlers()
    |> Enum.map(& &1.user_id)
    |> Enum.uniq()
    |> Enum.each(fn user_id ->
      Notifications.dispatch_event(:password_reset_requested, Map.put(payload, :user_id, user_id))
    end)
  end

  defp notify_completed(user_id),
    do: Notifications.dispatch_event(:password_reset_completed, %{user_id: user_id})

  defp log(event, person, handler) do
    Store.log(%{
      event: Atom.to_string(event),
      login_id: Map.get(person, :login_id),
      user_id: Map.get(person, :id) || Map.get(person, :user_id),
      handle: Map.get(person, :handle),
      handler_user_id: handler && handler.id,
      handler_handle: handler && Map.get(handler, :handle)
    })
  rescue
    error -> Logger.error("password reset log failed: #{Exception.message(error)}")
  end
end
