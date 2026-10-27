defmodule Palee.Identity.UserStore do
  @behaviour Palee.Identity.Ports.UserStore

  @impl true
  def create_login_with_profile(params), do: impl().create_login_with_profile(params)
  @impl true
  def create_demo_person(organization_id, params),
    do: impl().create_demo_person(organization_id, params)

  @impl true
  def demo_user_ids(organization_id), do: impl().demo_user_ids(organization_id)
  @impl true
  def visible_user_ids(user_ids, viewer_id), do: impl().visible_user_ids(user_ids, viewer_id)
  @impl true
  def add_profile(login_id, params), do: impl().add_profile(login_id, params)
  @impl true
  def get_login_by_email(email), do: impl().get_login_by_email(email)
  @impl true
  def get_by_email(email), do: impl().get_by_email(email)
  @impl true
  def list_profiles(login_id), do: impl().list_profiles(login_id)
  @impl true
  def touch_last_used(login_id, user_id), do: impl().touch_last_used(login_id, user_id)
  @impl true
  def handle_available?(handle, except_user_id \\ nil),
    do: impl().handle_available?(handle, except_user_id)

  @impl true
  def update_credentials(user_id, params), do: impl().update_credentials(user_id, params)
  @impl true
  def mark_email_verified(login_id, email, now),
    do: impl().mark_email_verified(login_id, email, now)

  @impl true
  def reset_login_password(login_id, password),
    do: impl().reset_login_password(login_id, password)

  @impl true
  def delete_user(user), do: impl().delete_user(user)
  @impl true
  def delete_tenant_scoped_user(user), do: impl().delete_tenant_scoped_user(user)
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
  def mark_tour_completed(user_id, audience), do: impl().mark_tour_completed(user_id, audience)

  @impl true
  def update_avatar(user_id, avatar_url), do: impl().update_avatar(user_id, avatar_url)

  @impl true
  def update_time_zone(user_id, time_zone), do: impl().update_time_zone(user_id, time_zone)

  @impl true
  def search_users(query), do: impl().search_users(query)

  @impl true
  def count_by_role(role), do: impl().count_by_role(role)

  @impl true
  def bump_security_version(user_id), do: impl().bump_security_version(user_id)

  defp impl do
    Application.fetch_env!(:palee, :identity_user_store)
  end
end
