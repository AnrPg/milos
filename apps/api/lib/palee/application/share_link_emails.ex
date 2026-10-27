defmodule Palee.Application.ShareLinkEmails do
  @moduledoc """
  ADR-210: "Send by email" next to a share link's share and copy buttons.
  The member types an address; Palee emails the same link they would have
  shared (`:share_link`, ADR-203), with their name and nothing else of
  theirs.

  The link is rebuilt here from what the member holds, never taken as a
  URL, and must be the sender's own and still usable:

    * `guest_pass`: a guest pass or host invitation token (`EventInvites`)
      the sender signed;
    * `buddy_invite`: a pending check-in buddy invite link of the sender;
    * `referral`: the sender's «Φέρε φίλο» code at a box.

  Abuse controls, in order: mock people of a demo business never send
  (`:not_live`), the sender's own email must be verified
  (`:share_link_sender_unverified`), at most
  `ShareLinkPolicy.daily_limit/0` a day per sender
  (`:share_link_daily_limit`). The outbox then refuses a suppressed or
  over-throttled recipient and, by the business's demo gate, a guest pass or
  referral of a demo business. Sending the same link to the same address
  again returns the first email.
  """

  alias Palee.Application.{EventInvites, PublicURL}
  alias Palee.{Buddies, Email, Identity, Referrals}
  alias Palee.Email.Domain.{Address, ShareLinkPolicy}

  @doc "Queues `params` (`link`, `token`, `to`) from `account`; `{:ok, delivery summary}`."
  def send(account, params, now \\ DateTime.utc_now())

  def send(%{id: sender_id} = account, params, now) when is_map(params) do
    with :ok <- real_person(account),
         :ok <- verified(account),
         {:ok, kind} <- kind(param(params, "link")),
         {:ok, link} <- resolve(kind, param(params, "token"), sender_id, now),
         {:ok, to} <- address(param(params, "to")),
         :ok <- within_limit(sender_id, now),
         {:ok, message} <- enqueue(account, kind, link, to, now) do
      Email.status(message.id)
    end
  end

  defp real_person(%{demo_organization_id: nil}), do: :ok
  defp real_person(%{demo_organization_id: _demo}), do: {:error, :not_live}
  defp real_person(_account), do: :ok

  defp verified(account) do
    if Identity.email_verified?(account), do: :ok, else: {:error, :share_link_sender_unverified}
  end

  defp kind(kind) do
    case ShareLinkPolicy.kind(kind) do
      {:ok, kind} -> {:ok, kind}
      :error -> {:error, :share_link_invalid}
    end
  end

  # -- the link -------------------------------------------------------------

  defp resolve(:guest_pass, token, sender_id, _now) when is_binary(token) do
    case EventInvites.verify(token) do
      {:ok, %{inviter_id: ^sender_id, event_id: event_id, organization_id: organization_id}} ->
        {:ok,
         %{ref: token, path: EventInvites.path(event_id, token), organization_id: organization_id}}

      _other ->
        {:error, :share_link_invalid}
    end
  end

  defp resolve(:buddy_invite, token, sender_id, now) when is_binary(token) do
    with {:ok, digest} <- Buddies.decode_invite_token(token),
         %{inviter_id: ^sender_id, status: "pending"} <- Buddies.invite_preview(digest, now) do
      {:ok, %{ref: token, path: Buddies.invite_path(token), organization_id: nil}}
    else
      _other -> {:error, :share_link_invalid}
    end
  end

  defp resolve(:referral, code, sender_id, _now) when is_binary(code) do
    with {:ok, code} <- Referrals.normalize_code(code),
         %{user_id: ^sender_id, organization_id: organization_id} <- Referrals.resolve_code(code) do
      {:ok, %{ref: code, path: "/r/" <> code, organization_id: organization_id}}
    else
      _other -> {:error, :share_link_invalid}
    end
  end

  defp resolve(_kind, _token, _sender_id, _now), do: {:error, :share_link_invalid}

  # -- sending --------------------------------------------------------------

  defp address(to) do
    case Address.normalize(to) do
      {:ok, address} -> {:ok, address}
      _invalid -> {:error, :invalid_address}
    end
  end

  defp within_limit(sender_id, now) do
    sent = Email.list_by_idempotency_prefix(ShareLinkPolicy.sender_prefix(sender_id))
    if ShareLinkPolicy.within_limit?(sent, now), do: :ok, else: {:error, :share_link_daily_limit}
  end

  defp enqueue(account, kind, link, to, now) do
    assigns = %{
      link: kind,
      name: ShareLinkPolicy.sender_name(account.nickname, Map.get(account, :handle)),
      url: PublicURL.base_url() <> link.path
    }

    Email.enqueue(:share_link, to, assigns,
      locale: locale(account),
      organization_id: link.organization_id,
      idempotency_key: ShareLinkPolicy.key(account.id, kind, link.ref, to),
      now: now
    )
  end

  defp locale(account) do
    case Palee.Identity.Domain.Locale.normalize(Map.get(account, :preferred_locale)) do
      {:ok, locale} -> locale
      {:error, _unsupported} -> "en"
    end
  end

  defp param(params, key), do: Map.get(params, key) || Map.get(params, String.to_atom(key))
end
