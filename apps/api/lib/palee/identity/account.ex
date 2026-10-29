defmodule Palee.Identity.Account do
  @moduledoc false

  @enforce_keys [:id, :nickname, :role]
  defstruct [
    :id,
    # The display name (ADR-187): free, not unique, shown everywhere. Kept
    # under its historical key because every presenter reads it.
    :nickname,
    # The unique @handle; `normalized_nickname` is its historical alias.
    :handle,
    :normalized_nickname,
    # ADR-187: hidden folded search key (display name in its own script,
    # its Latin form, and the handle).
    :search_text,
    :login_id,
    :handle_changed_at,
    :role,
    :password_hash,
    :calendar_feed_token_version,
    :security_version,
    :avatar_url,
    :preferred_locale,
    :preferred_theme_slug,
    # ADR-179: the IANA zone the person's device last reported (nil: never).
    :time_zone,
    # The login's email (ADR-187), shared by every profile of that login.
    # Carried on the domain struct so invitation email binding can be checked
    # without reaching for the Ecto schema.
    :email,
    # When the login proved it can read `email` (an emailed link was opened);
    # nil while unverified. Features that trust the address check this.
    :email_verified_at,
    :inserted_at,
    # ADR-184: the demo business a mock person belongs to; nil for real people.
    :demo_organization_id,
    # ADR-254: the business whose import created this profile, until the
    # person claims it by proving the inbox; nil otherwise.
    :held_by_organization_id,
    completed_tours: []
  ]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          nickname: String.t(),
          handle: String.t() | nil,
          normalized_nickname: String.t() | nil,
          login_id: Ecto.UUID.t() | nil,
          handle_changed_at: DateTime.t() | nil,
          role: atom(),
          password_hash: String.t() | nil,
          calendar_feed_token_version: integer() | nil,
          security_version: integer() | nil,
          avatar_url: String.t() | nil,
          preferred_locale: String.t() | nil,
          preferred_theme_slug: String.t() | nil,
          time_zone: String.t() | nil,
          email: String.t() | nil,
          email_verified_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | NaiveDateTime.t() | nil,
          demo_organization_id: Ecto.UUID.t() | nil,
          held_by_organization_id: Ecto.UUID.t() | nil
        }
end
