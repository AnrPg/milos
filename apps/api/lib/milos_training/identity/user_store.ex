defmodule MilosTraining.Identity.UserStore do
  @behaviour MilosTraining.Identity.Ports.UserStore

  @impl true
  def create_user(params), do: impl().create_user(params)
  @impl true
  def delete_user(user), do: impl().delete_user(user)
  @impl true
  def update_user_role(user, role), do: impl().update_user_role(user, role)
  @impl true
  def regenerate_calendar_feed_token(user), do: impl().regenerate_calendar_feed_token(user)
  @impl true
  def get_by_nickname(nickname), do: impl().get_by_nickname(nickname)
  @impl true
  def get_by_id(id), do: impl().get_by_id(id)
  @impl true
  def list_by_ids(ids), do: impl().list_by_ids(ids)
  @impl true
  def list_by_role(role), do: impl().list_by_role(role)
  @impl true
  def list_all_users, do: impl().list_all_users()
  @impl true
  def search_athletes(query), do: impl().search_athletes(query)

  @impl true
  def update_profile(user_id, params), do: impl().update_profile(user_id, params)

  @impl true
  def update_avatar(user_id, avatar_url), do: impl().update_avatar(user_id, avatar_url)

  @impl true
  def search_users(query), do: impl().search_users(query)

  @impl true
  def count_by_role(role), do: impl().count_by_role(role)

  defp impl do
    Application.get_env(
      :milos_training,
      :identity_user_store,
      MilosTraining.Infrastructure.Identity.EctoUserStore
    )
  end
end
