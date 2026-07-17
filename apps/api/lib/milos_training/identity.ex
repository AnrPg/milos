defmodule MilosTraining.Identity do
  alias MilosTraining.Identity.Commands.{RegisterAdmin, RegisterUser, UpdateRole}
  alias MilosTraining.Identity.Domain.Locale
  alias MilosTraining.Identity.Queries.FindUser
  alias MilosTraining.Identity.UserStore

  defdelegate register(params), to: RegisterUser, as: :call
  defdelegate register_admin(params), to: RegisterAdmin, as: :call
  defdelegate find_by_nickname(nickname), to: FindUser, as: :by_nickname
  defdelegate find_by_id(id), to: FindUser, as: :by_id
  defdelegate list_by_ids(ids), to: FindUser, as: :list_by_ids
  defdelegate list_by_role(role), to: FindUser, as: :list_by_role
  defdelegate list_all_users(), to: FindUser, as: :list_all
  defdelegate search_athletes(query), to: FindUser, as: :search_athletes
  defdelegate delete(user), to: UserStore, as: :delete_user
  defdelegate update_role(user, role), to: UpdateRole, as: :call
  defdelegate regenerate_calendar_feed_token(user), to: UserStore
  defdelegate update_profile(user_id, params), to: UserStore
  defdelegate update_avatar(user_id, avatar_url), to: UserStore
  defdelegate search_users(query), to: UserStore
  defdelegate count_by_role(role), to: UserStore
  defdelegate bump_security_version(user_id), to: UserStore
  defdelegate supported_locales(), to: Locale, as: :supported
end
