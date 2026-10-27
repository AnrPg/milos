defmodule Palee.Application.EmailVerification do
  @moduledoc """
  ADR-213: proving that a login can read its email address.

  - **At sign-up** (`after_sign_up/1`) a new login gets one `:verify_email`
    email. Adding a profile to an existing login sends nothing. People use
    the app at once; the address is simply unverified until the link is
    opened.
  - **Resend** (`resend/2`) issues a fresh link (the older unused one stops
    working) within the template's throttle, and says how long to wait when
    it is throttled.
  - **Verify** (`verify/2`) spends the link and marks the login's current
    address verified. A link to an address the login no longer has is
    refused (`:email_mismatch`).

  `send_verification/2` is the reusable part (the email change flow can send
  the same email to a new address). The link is
  `<public url>/verify-email#token=...`: the token rides in the fragment so
  mail scanners and server logs never see it, and the page posts it.

  `config :palee, :auto_verify_email, true` (dev only, `AUTO_VERIFY_EMAIL`)
  marks new logins verified instead of emailing them.
  """

  alias Palee.Application.PublicURL
  alias Palee.Email
  alias Palee.Email.LinkTokens
  alias Palee.Email.Templates.VerifyEmail
  alias Palee.Identity

  @purpose "verify_email"
  @day_seconds 86_400
  # Messages that never reached anyone do not count toward the throttle (ADR-203).
  @uncounted ~w(failed suppressed)

  @type account :: %{
          required(:login_id) => binary() | nil,
          required(:email) => String.t() | nil,
          optional(atom()) => term()
        }

  @doc """
  The sign-up email of a new login. Does nothing for a login that already
  has other profiles, is verified, or already got its sign-up email. Always
  `:ok`: a mail problem never fails a registration.
  """
  @spec after_sign_up(account()) :: :ok
  def after_sign_up(%{login_id: login_id} = account) when is_binary(login_id) do
    cond do
      Identity.email_verified?(account) ->
        :ok

      auto_verify?() ->
        _ = Identity.mark_email_verified(login_id, account.email)
        :ok

      first_profile?(login_id) and not sign_up_email_sent?(login_id) ->
        _ = send_verification(account, variant: "sign_up")
        :ok

      true ->
        :ok
    end
  end

  def after_sign_up(_account), do: :ok

  @doc """
  Emails `account`'s login a verification link to `opts[:to]` (default: its
  current email). Options: `:to`, `:variant` (part of the idempotency key,
  default a fresh one per link), `:now`.

  `{:ok, message}`, `{:error, {:throttled, retry_after_seconds}}`, or an
  enqueue error (`:invalid_address`, `:suppressed`, `:over_budget`, ...).
  """
  @spec send_verification(account(), keyword()) ::
          {:ok, Email.Message.t()} | {:error, {:throttled, pos_integer()} | atom() | term()}
  def send_verification(%{login_id: login_id} = account, opts \\ []) when is_binary(login_id) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    to = Keyword.get(opts, :to) || account.email

    # Checked before a link is issued: a new link replaces the older unused
    # one, so a throttled resend must not kill the link already in the inbox.
    with :ok <- throttle(login_id, now),
         {:ok, raw, token} <-
           LinkTokens.issue(@purpose, login_id,
             user_id: Map.get(account, :id),
             target_email: to,
             now: now
           ) do
      variant = Keyword.get(opts, :variant) || token.id

      result =
        Email.enqueue(
          :verify_email,
          to,
          %{name: display_name(account), email: to, url: link(raw)},
          locale: email_locale(account),
          login_id: login_id,
          user_id: Map.get(account, :id),
          idempotency_key: "#{key_prefix(login_id)}#{variant}",
          now: now
        )

      case result do
        {:error, :throttled} ->
          {:error, {:throttled, VerifyEmail.throttle().min_interval_seconds}}

        other ->
          other
      end
    end
  end

  @doc """
  The signed-in person asks for a new link: `{:ok, :sent}`,
  `{:ok, :already_verified}`, `{:error, {:throttled, retry_after_seconds}}`
  or an enqueue error.
  """
  @spec resend(account(), keyword()) ::
          {:ok, :sent | :already_verified} | {:error, term()}
  def resend(account, opts \\ [])

  def resend(%{login_id: login_id} = account, opts) when is_binary(login_id) do
    if Identity.email_verified?(account) do
      {:ok, :already_verified}
    else
      with {:ok, _message} <- send_verification(account, opts), do: {:ok, :sent}
    end
  end

  def resend(_account, _opts), do: {:error, :no_login}

  @doc """
  Spends a verification link. `:ok`, or `{:error, reason}` with `:invalid`,
  `:expired`, `:used` or `:email_mismatch` (the login's email changed since
  the link was sent).
  """
  @spec verify(String.t(), DateTime.t()) ::
          :ok | {:error, :invalid | :expired | :used | :email_mismatch}
  def verify(raw_token, now \\ DateTime.utc_now())

  def verify(raw_token, now) when is_binary(raw_token) and raw_token != "" do
    with {:ok, token} <- LinkTokens.consume(@purpose, raw_token, now) do
      Identity.mark_email_verified(token.login_id, token.target_email, now)
    end
  end

  def verify(_raw_token, _now), do: {:error, :invalid}

  @doc "The verification link for a raw token."
  def link(raw_token), do: PublicURL.base_url() <> "/verify-email#token=" <> raw_token

  # -- throttle ------------------------------------------------------------------

  # The outbox enforces the throttle per address; this mirrors it per login
  # from the login's own verification emails, so the answer can say how long
  # to wait (ADR-213).
  defp throttle(login_id, now) do
    %{min_interval_seconds: interval, max_per_day: max} = VerifyEmail.throttle()
    since = DateTime.add(now, -@day_seconds, :second)

    recent =
      login_id
      |> key_prefix()
      |> Email.list_by_idempotency_prefix()
      |> Enum.reject(&(&1.status in @uncounted))
      |> Enum.map(& &1.inserted_at)
      |> Enum.filter(&(DateTime.compare(&1, since) == :gt))
      |> Enum.sort(DateTime)

    case retry_after(recent, interval, max, now) do
      0 -> :ok
      seconds -> {:error, {:throttled, seconds}}
    end
  end

  defp retry_after([], _interval, _max, _now), do: 0

  defp retry_after(recent, interval, max, now) do
    next_by_interval = DateTime.diff(DateTime.add(List.last(recent), interval, :second), now)

    next_by_count =
      if length(recent) >= max,
        do: DateTime.diff(DateTime.add(Enum.at(recent, -max), @day_seconds, :second), now),
        else: 0

    max(max(next_by_interval, next_by_count), 0)
  end

  # -- helpers -------------------------------------------------------------------

  defp first_profile?(login_id), do: length(Identity.list_profiles(login_id)) == 1

  defp sign_up_email_sent?(login_id),
    do: Email.list_by_idempotency_prefix("#{key_prefix(login_id)}sign_up") != []

  defp key_prefix(login_id), do: "verify_email:#{login_id}:"

  # `nickname` is the display name (ADR-187).
  defp display_name(account), do: Map.get(account, :nickname)

  defp email_locale(account), do: Map.get(account, :preferred_locale) || "en"

  defp auto_verify?, do: Application.get_env(:palee, :auto_verify_email, false) == true
end
