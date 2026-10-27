defmodule Palee.Organizations.Domain.InvitationEmailPolicy do
  @moduledoc """
  ADR-209: the rules of invitations a box sends by email. Pure.

    * One request sends to at most `per_request` addresses (200).
    * Per rolling 24 h, a box emails at most `per_organization_day` (300)
      invitations and one inviter at most `per_inviter_day` (200). A bulk
      request that would pass a cap is refused whole, with how many are
      left, so nobody gets half a list.
    * The delivery status the pending list shows, from the outbox status.
    * A resent invitation keeps the lifetime of the one it replaces.
  """

  @default_limits %{per_request: 200, per_organization_day: 300, per_inviter_day: 200}
  @min_lifetime 300
  @max_lifetime 604_800

  @type limits :: %{
          per_request: pos_integer(),
          per_organization_day: pos_integer(),
          per_inviter_day: pos_integer()
        }

  @doc "The default limits; `config :palee, :invitation_email_limits` overrides them."
  @spec default_limits() :: limits()
  def default_limits, do: @default_limits

  @doc "The limits with `overrides` (a keyword or map) applied."
  @spec limits(keyword() | map()) :: limits()
  def limits(overrides),
    do: Map.merge(@default_limits, overrides |> Map.new() |> Map.take(Map.keys(@default_limits)))

  @doc """
  The addresses of a bulk request: a list, or one pasted text or CSV (split
  on commas, semicolons, whitespace and quotes), trimmed, lower-cased and
  without repeats, in their first order. Anything that is not shaped like
  an address is returned separately, so the box sees what was skipped.
  """
  @spec parse_addresses(term()) :: {[String.t()], [String.t()]}
  def parse_addresses(input) do
    input
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.flat_map(&String.split(&1, ~r/[\s,;"']+/u, trim: true))
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
    |> Enum.split_with(&address?/1)
  end

  @doc "Whether a value is shaped like one address (the outbox checks it fully)."
  @spec address?(term()) :: boolean()
  def address?(value) when is_binary(value),
    do: String.length(value) <= 254 and value =~ ~r/\A[^@\s<>()]+@[^@\s<>()]+\.[^@\s<>()]+\z/u

  def address?(_value), do: false

  @doc """
  `:ok` when `wanted` more emails stay within the request size and the
  daily caps given what was already `sent` (`%{organization:, inviter:}`);
  else `{:error, :too_many_invitation_emails}` or
  `{:error, :invitation_email_cap_reached, remaining}`.
  """
  @spec check(non_neg_integer(), %{organization: integer(), inviter: integer()}, limits()) ::
          :ok
          | {:error, :too_many_invitation_emails}
          | {:error, :invitation_email_cap_reached, non_neg_integer()}
  def check(wanted, sent, limits) do
    remaining =
      max(
        0,
        min(
          limits.per_organization_day - sent.organization,
          limits.per_inviter_day - sent.inviter
        )
      )

    cond do
      wanted > limits.per_request -> {:error, :too_many_invitation_emails}
      wanted > remaining -> {:error, :invitation_email_cap_reached, remaining}
      true -> :ok
    end
  end

  @doc """
  What the pending list shows for an emailed invitation: `queued` (also
  while deferred to tomorrow's budget), `sent`, `failed`, `bounced` (sent,
  but the address bounced or complained since) or `suppressed` (never sent:
  the address was already blocked). `nil` without a message.
  """
  @spec delivery_status(String.t() | nil, boolean()) :: String.t() | nil
  def delivery_status(nil, _suppressed_now?), do: nil
  def delivery_status(status, _suppressed?) when status in ["queued", "deferred"], do: "queued"
  def delivery_status("sent", true), do: "bounced"
  def delivery_status("sent", false), do: "sent"
  def delivery_status("bounced", _suppressed?), do: "bounced"
  def delivery_status("suppressed", _suppressed?), do: "suppressed"
  def delivery_status(_failed, _suppressed?), do: "failed"

  @doc "The lifetime, in seconds, of an invitation that replaces `invitation`."
  @spec resend_lifetime(%{
          required(:inserted_at) => DateTime.t(),
          required(:expires_at) => DateTime.t(),
          optional(atom()) => any()
        }) :: pos_integer()
  def resend_lifetime(%{inserted_at: inserted_at, expires_at: expires_at}) do
    expires_at
    |> DateTime.diff(inserted_at, :second)
    |> max(@min_lifetime)
    |> min(@max_lifetime)
  end
end
