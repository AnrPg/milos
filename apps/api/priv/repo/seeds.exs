# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     MilosTraining.Repo.insert!(%MilosTraining.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias MilosTraining.Identity

if Mix.env() == :dev do
  admin_nickname = System.get_env("DEV_ADMIN_NICKNAME", "admin")
  admin_password = System.get_env("DEV_ADMIN_PASSWORD", "AdminPass123!")

  admin =
    case Identity.find_by_nickname(admin_nickname) do
      nil ->
        {:ok, user} =
          Identity.register(%{
            nickname: admin_nickname,
            password: admin_password,
            role: :member
          })

        {:ok, admin_user} = Identity.update_role(user, :admin)
        admin_user

      %{role: :admin} = user ->
        user

      user ->
        {:ok, admin_user} = Identity.update_role(user, :admin)
        admin_user
    end

  IO.puts("Ensured development admin account: #{admin.nickname}")
end
