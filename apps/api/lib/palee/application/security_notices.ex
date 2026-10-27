defmodule Palee.Application.SecurityNotices do
  @moduledoc """
  Tells a person by email (category :security, ADR-203) that something
  happened to their login's credentials or sessions. Never carries a secret.
  Security notices are mandatory: there is no opt-out, and the footer says so
  (ADR-208).

  Events: `:password_changed`, `:password_reset_completed`,
  `:email_change_requested`, `:email_changed`, `:recovery_code_used`,
  `:recovery_codes_regenerated`, `:recovery_codes_running_low`,
  `:signed_out_everywhere`, `:profile_added`, `:new_sign_in`,
  `:account_deletion_scheduled`, `:account_deleted`. Each has its own
  template, kind `:security_<event>`.

  `meta` may carry:

    * `:to` - an address other than the login's current one (the old
      address after an email change, the address of a deleted login);
    * `:at` - when it happened (default now), shown on the person's clock
      (ADR-179), or in UTC with the zone named when their zone is unknown;
    * `:device` (`%{client:, platform:}` or words) or `:user_agent`, and
      `:ip` (a tuple or a string; only its network part is shown), `:place`;
    * `:revert_url` (email change), `:undo_url` (account deletion),
      `:sign_out_url` (else a fresh `sign_out_everywhere` link is issued);
    * `:remaining` (recovery codes left), `:email` / `:new_email` (the new
      address of an email change), `:profile` (the profile added or
      deleted), `:scope` (`:profile | :login`) and `:scheduled_for` (deletion);
    * `:occurrence` - a stable id of this occurrence, so a retried caller
      does not send twice (the idempotency key is
      `security_notice:<event>:<login or profile id>:<occurrence>`); without
      one every call is its own occurrence.

  The account is never reloaded: pass it as it is (for `:account_deleted`,
  as it was before the deletion).
  """

  require Logger

  alias Palee.Application.PublicURL
  alias Palee.Email
  alias Palee.Email.LinkTokens
  alias Palee.Identity.Domain.{Locale, SignInDevice}
  alias Palee.TimeZones.ZonedTime

  @events ~w(password_changed password_reset_completed email_change_requested email_changed
             recovery_code_used recovery_codes_regenerated recovery_codes_running_low
             signed_out_everywhere profile_added new_sign_in
             account_deletion_scheduled account_deleted)a

  # Events whose reader can't act by signing out: it already happened, or
  # there is nothing left to sign out.
  @without_sign_out ~w(recovery_codes_running_low signed_out_everywhere account_deleted)a

  def events, do: @events

  @doc "The email kind of an event."
  def kind(event) when event in @events, do: :"security_#{event}"

  @doc "Queues the notice; always `:ok` so a mail problem never fails the action."
  def notify(event, account, meta \\ %{}) when event in @events do
    meta = Map.new(meta)

    case address(account, meta) do
      nil -> :ok
      to -> deliver(event, account, to, meta)
    end
  rescue
    error ->
      Logger.error("security_notice_failed event=#{event} error=#{Exception.message(error)}")
      :ok
  end

  defp deliver(event, account, to, meta) do
    # `:at` is only what the email shows; links and budgets run on the real clock.
    now = DateTime.utc_now()
    at = Map.get(meta, :at) || now
    zone = Map.get(account, :time_zone)

    assigns = %{
      name: Map.get(account, :nickname),
      at: moment(at, zone),
      device: device(meta),
      ip: coarse_ip(Map.get(meta, :ip)),
      place: Map.get(meta, :place),
      sign_out_url: sign_out_url(event, account, to, meta, now),
      reset_url: url("/forgot-password"),
      settings_url: url("/me/settings#security"),
      revert_url: Map.get(meta, :revert_url),
      undo_url: Map.get(meta, :undo_url),
      remaining: Map.get(meta, :remaining),
      email: Map.get(meta, :new_email) || Map.get(meta, :email),
      profile: Map.get(meta, :profile) || profile_name(event, account),
      scope: Map.get(meta, :scope, :login),
      date: scheduled(Map.get(meta, :scheduled_for), zone)
    }

    opts = [
      locale: locale(account),
      login_id: Map.get(account, :login_id),
      user_id: Map.get(account, :id),
      idempotency_key: idempotency_key(event, account, meta)
    ]

    case Email.enqueue(kind(event), to, assigns, opts) do
      {:ok, _message} ->
        :ok

      {:error, reason} ->
        Logger.warning("security_notice_not_sent event=#{event} reason=#{inspect(reason)}")
        :ok
    end
  end

  defp address(account, meta) do
    case Map.get(meta, :to) || (is_map(account) && Map.get(account, :email)) do
      to when is_binary(to) and to != "" -> to
      _none -> nil
    end
  end

  defp locale(account) do
    case Locale.normalize(Map.get(account, :preferred_locale)) do
      {:ok, locale} -> locale
      _unsupported -> Locale.default()
    end
  end

  defp idempotency_key(event, account, meta) do
    owner = Map.get(account, :login_id) || Map.get(account, :id) || "unknown"
    occurrence = Map.get(meta, :occurrence) || Ecto.UUID.generate()
    "security_notice:#{event}:#{owner}:#{occurrence}"
  end

  # A fresh "sign out everywhere" link (7 days; every notice keeps its own).
  defp sign_out_url(event, _account, _to, _meta, _now) when event in @without_sign_out, do: nil

  defp sign_out_url(_event, account, to, meta, now) do
    case {Map.get(meta, :sign_out_url), Map.get(account, :login_id)} do
      {url, _login_id} when is_binary(url) ->
        url

      {nil, login_id} when is_binary(login_id) ->
        {:ok, raw, _token} =
          LinkTokens.issue(:sign_out_everywhere, login_id,
            user_id: Map.get(account, :id),
            target_email: to,
            now: now
          )

        url("/sign-out-everywhere#token=" <> raw)

      _no_login ->
        nil
    end
  end

  # «27/10/2026 14:05 (Athens)» on the person's clock; «27/10/2026 12:05 UTC»
  # while their zone is unknown (ADR-179).
  @doc false
  def moment(%DateTime{} = at, zone) do
    if ZonedTime.valid?(zone) and not ZonedTime.utc?(zone) do
      Calendar.strftime(ZonedTime.local(at, zone), "%d/%m/%Y %H:%M") <>
        " (" <> ZonedTime.label(zone) <> ")"
    else
      Calendar.strftime(ZonedTime.local(at, "Etc/UTC"), "%d/%m/%Y %H:%M") <> " UTC"
    end
  end

  defp scheduled(%DateTime{} = at, zone), do: moment(at, zone)
  defp scheduled(_at, _zone), do: nil

  defp device(meta) do
    case Map.get(meta, :device) do
      nil -> meta |> Map.get(:user_agent) |> described()
      device -> device
    end
  end

  defp described(user_agent) when is_binary(user_agent), do: SignInDevice.describe(user_agent)
  defp described(_user_agent), do: nil

  defp coarse_ip(ip) when is_tuple(ip), do: SignInDevice.coarse_ip(ip)

  defp coarse_ip(ip) when is_binary(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, parsed} -> SignInDevice.coarse_ip(parsed)
      {:error, _reason} -> nil
    end
  end

  defp coarse_ip(_ip), do: nil

  defp profile_name(event, account)
       when event in [:account_deletion_scheduled, :account_deleted] do
    case Map.get(account, :handle) do
      handle when is_binary(handle) -> "@" <> handle
      _none -> Map.get(account, :nickname)
    end
  end

  defp profile_name(_event, _account), do: nil

  defp url(path), do: String.trim_trailing(PublicURL.base_url(), "/") <> path
end
