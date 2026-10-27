defmodule Palee.Email.Domain.LinkTokenPolicy do
  @moduledoc """
  Single-use email links (ADR-203). A link carries 32 random bytes,
  url-safe base64 without padding (43 characters); only their SHA-256 is
  stored, so a database read never yields a usable link.

  Each purpose has a lifetime, and says whether issuing a new link
  invalidates the person's older unused ones (`replaces_previous`): a new
  password reset link makes the last one useless, but every email change
  keeps its own revert link.
  """

  @purposes %{
    "verify_email" => %{ttl_seconds: 48 * 3_600, replaces_previous: true},
    "email_change" => %{ttl_seconds: 24 * 3_600, replaces_previous: true},
    "email_change_revert" => %{ttl_seconds: 7 * 24 * 3_600, replaces_previous: false},
    "password_reset" => %{ttl_seconds: 3_600, replaces_previous: true},
    "account_deletion" => %{ttl_seconds: 24 * 3_600, replaces_previous: true},
    "sign_out_everywhere" => %{ttl_seconds: 7 * 24 * 3_600, replaces_previous: true}
  }

  @token_bytes 32

  @doc "The known purposes."
  def purposes, do: @purposes |> Map.keys() |> Enum.sort()

  @doc "`{:ok, \"purpose\"}` for a known purpose (atom or string), else `:error`."
  def purpose(purpose) when is_atom(purpose) and not is_nil(purpose),
    do: purpose(Atom.to_string(purpose))

  def purpose(purpose) when is_binary(purpose),
    do: if(Map.has_key?(@purposes, purpose), do: {:ok, purpose}, else: :error)

  def purpose(_purpose), do: :error

  @doc "The default lifetime of a purpose's link, in seconds."
  def ttl_seconds(purpose), do: Map.fetch!(@purposes, purpose).ttl_seconds

  @doc "Whether a new link of this purpose invalidates the older unused ones."
  def replaces_previous?(purpose), do: Map.fetch!(@purposes, purpose).replaces_previous

  @doc "When a link issued at `now` stops working (`ttl_seconds` overrides the default)."
  def expires_at(purpose, %DateTime{} = now, ttl_seconds \\ nil),
    do: DateTime.add(now, ttl_seconds || ttl_seconds(purpose), :second)

  @doc "A new raw token: 32 random bytes, url-safe base64."
  def generate,
    do: @token_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  @doc "The stored form of a raw token."
  def hash(raw) when is_binary(raw), do: :crypto.hash(:sha256, raw)

  @doc "Whether a raw token is shaped like one `generate/0` makes (no lookup for junk)."
  def well_formed?(raw) when is_binary(raw), do: byte_size(raw) == 43 and raw =~ ~r/\A[A-Za-z0-9_-]+\z/
  def well_formed?(_raw), do: false

  @doc "Whether the link's lifetime is over at `now`."
  def expired?(%{expires_at: expires_at}, %DateTime{} = now),
    do: DateTime.compare(now, expires_at) != :lt

  @doc "Whether the link may still be used at `now`: never used and not expired."
  def usable?(token, now), do: is_nil(token.used_at) and not expired?(token, now)

  @doc "`:ok`, or why the link cannot be used: `:used` first, then `:expired`."
  def check(%{used_at: used_at}, _now) when not is_nil(used_at), do: {:error, :used}
  def check(token, now), do: if(expired?(token, now), do: {:error, :expired}, else: :ok)
end
