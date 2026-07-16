defmodule MilosTraining.Identity.Account do
  @moduledoc false

  @enforce_keys [:id, :nickname, :role]
  defstruct [
    :id,
    :nickname,
    :role,
    :password_hash,
    :calendar_feed_token_version,
    :security_version,
    :avatar_url,
    :preferred_locale,
    :inserted_at
  ]
end
