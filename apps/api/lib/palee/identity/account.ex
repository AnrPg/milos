defmodule Palee.Identity.Account do
  @moduledoc false

  @enforce_keys [:id, :nickname, :role]
  defstruct [
    :id,
    :nickname,
    :normalized_nickname,
    :role,
    :password_hash,
    :calendar_feed_token_version,
    :security_version,
    :avatar_url,
    :preferred_locale,
    :preferred_theme_slug,
    # ADR-177: the IANA zone the person's device last reported (nil: never).
    :time_zone,
    # Nullable: accounts created before F-10 have none. Carried on the domain
    # struct so invitation email binding can be checked without reaching for
    # the Ecto schema.
    :email,
    :inserted_at,
    completed_tours: []
  ]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          nickname: String.t(),
          normalized_nickname: String.t() | nil,
          role: atom(),
          password_hash: String.t() | nil,
          calendar_feed_token_version: integer() | nil,
          security_version: integer() | nil,
          avatar_url: String.t() | nil,
          preferred_locale: String.t() | nil,
          preferred_theme_slug: String.t() | nil,
          time_zone: String.t() | nil,
          email: String.t() | nil,
          inserted_at: DateTime.t() | NaiveDateTime.t() | nil
        }
end
