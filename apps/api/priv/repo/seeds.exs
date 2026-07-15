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

alias MilosTraining.{Identity, Repo}
alias MilosTraining.Gamification.TrainingQuote

quotes = [
  %{body: "The only bad workout is the one that didn't happen.", author: nil},
  %{body: "Your body can stand almost anything. It's your mind you have to convince.", author: nil},
  %{body: "Sweat is just fat crying.", author: nil},
  %{body: "Don't stop when you're tired. Stop when you're done.", author: nil},
  %{body: "Push yourself because no one else is going to do it for you.", author: nil},
  %{body: "Wake up. Work out. Look hot. Kick ass.", author: nil},
  %{body: "Champions aren't made in the gyms. Champions are made from something they have deep inside them — a desire, a dream, a vision.", author: "Muhammad Ali"},
  %{body: "The clock is ticking. Are you becoming the person you want to be?", author: nil},
  %{body: "No matter how slow you go, you are still lapping everybody on the couch.", author: nil},
  %{body: "Train insane or remain the same.", author: nil},
  %{body: "It never gets easier. You just get stronger.", author: nil},
  %{body: "Discipline is doing what needs to be done, even when you don't want to do it.", author: nil},
  %{body: "Your health is an investment, not an expense.", author: nil},
  %{body: "Pain is temporary. Quitting lasts forever.", author: "Lance Armstrong"},
  %{body: "What seems impossible today will one day become your warm-up.", author: nil},
  %{body: "Take care of your body. It's the only place you have to live.", author: "Jim Rohn"},
  %{body: "The difference between try and triumph is just a little umph.", author: nil},
  %{body: "Strong people are harder to kill than weak people and more useful in general.", author: "Mark Rippetoe"},
  %{body: "Success usually comes to those who are too busy to be looking for it.", author: "Henry David Thoreau"},
  %{body: "The gym is the one place where you can be in complete control of your progress.", author: nil}
]

existing_count = Repo.aggregate(TrainingQuote, :count)

if existing_count == 0 do
  Enum.each(quotes, fn attrs ->
    %TrainingQuote{} |> TrainingQuote.changeset(attrs) |> Repo.insert!()
  end)

  IO.puts("Seeded #{length(quotes)} training quotes.")
end

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
