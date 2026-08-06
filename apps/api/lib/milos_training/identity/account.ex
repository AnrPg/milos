defmodule MilosTraining.Identity.Account do
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
    # Nullable: accounts created before F-10 have none. Carried on the domain
    # struct so invitation email binding can be checked without reaching for
    # the Ecto schema.
    :email,
    :inserted_at
  ]
end
