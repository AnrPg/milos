defmodule Palee.Application.PasswordRecovery do
  @moduledoc """
  ADR-187: password recovery without a mail service.

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

  alias Palee.Application.PasswordVerifier
  alias Palee.Identity
  alias Palee.Identity.Domain.{PasswordResetPolicy, RecoveryCodes}
  alias Palee.Identity.PasswordResetStore, as: Store
  alias Palee.Identity.RegistrationPolicy
  alias Palee.Notifications

  @log_limit 500

  # -- the person ----------------------------------------------------------

  @doc """
  Files a request for the account named by `identifier` (an email or an
  @handle). Always `:ok`: whether the account exists, or already has an open
  request, is not revealed.
  """
  def request(identifier, now \\ DateTime.utc_now())

  def request(identifier, now) when is_binary(identifier) do
    with %{} = person <- find(identifier),
         nil <- Store.get_request_for_login(person.login_id),
         {:ok, request} <- Store.create_request(%{login_id: person.login_id, user_id: person.id}) do
      log(:requested, person, nil)
      notify_handlers(request, person, now)
    end

    :ok
  end

  def request(_identifier, _now), do: :ok

  @doc "Sets a new password with a reset link's token."
  def complete(token, password, now \\ DateTime.utc_now())

  def complete(token, password, now) when is_binary(token) and is_binary(password) do
    with {:password, true} <- {:password, RegistrationPolicy.valid_password?(password)},
         %{} = request <-
           Store.get_request_by_token_hash(PasswordResetPolicy.hash_token(token)) ||
             {:error, :invalid_reset_link},
         false <- PasswordResetPolicy.expired?(request, now),
         :ok <- Identity.reset_login_password(request.login_id, password) do
      :ok = Store.delete_request(request.id)
      person = Identity.find_by_id(request.user_id)

      handler =
        request.link_issued_by_user_id && Identity.find_by_id(request.link_issued_by_user_id)

      log(:completed, person || %{id: request.user_id, login_id: request.login_id}, handler)
      notify_completed(request.user_id)
      :ok
    else
      {:password, false} -> {:error, :weak_password}
      true -> {:error, :expired_reset_link}
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
  def generate_codes(%{login_id: login_id, password_hash: hash}, current_password) do
    if is_binary(current_password) and PasswordVerifier.verify(current_password, hash) do
      codes = RecoveryCodes.generate()
      :ok = Store.replace_recovery_codes(login_id, Enum.map(codes, &RecoveryCodes.hash/1))
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
