defmodule MilosTraining.Application.UpdateAvatar do
  alias MilosTraining.Identity

  def call(user_id, avatar_url) do
    Identity.update_avatar(user_id, avatar_url)
  end
end
