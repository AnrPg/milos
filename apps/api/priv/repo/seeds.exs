# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Palee.Repo.insert!(%Palee.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Palee.{Identity, Organizations, Repo, Workouts}
alias Palee.Gamification.TrainingQuote

quotes = [
  %{body: "The only bad workout is the one that didn't happen.", author: nil},
  %{
    body: "Your body can stand almost anything. It's your mind you have to convince.",
    author: nil
  },
  %{body: "Sweat is just fat crying.", author: nil},
  %{body: "Don't stop when you're tired. Stop when you're done.", author: nil},
  %{body: "Push yourself because no one else is going to do it for you.", author: nil},
  %{body: "Wake up. Work out. Look hot. Kick ass.", author: nil},
  %{
    body:
      "Champions aren't made in the gyms. Champions are made from something they have deep inside them — a desire, a dream, a vision.",
    author: "Muhammad Ali"
  },
  %{body: "The clock is ticking. Are you becoming the person you want to be?", author: nil},
  %{
    body: "No matter how slow you go, you are still lapping everybody on the couch.",
    author: nil
  },
  %{body: "Train insane or remain the same.", author: nil},
  %{body: "It never gets easier. You just get stronger.", author: nil},
  %{
    body: "Discipline is doing what needs to be done, even when you don't want to do it.",
    author: nil
  },
  %{body: "Your health is an investment, not an expense.", author: nil},
  %{body: "Pain is temporary. Quitting lasts forever.", author: "Lance Armstrong"},
  %{body: "What seems impossible today will one day become your warm-up.", author: nil},
  %{body: "Take care of your body. It's the only place you have to live.", author: "Jim Rohn"},
  %{body: "The difference between try and triumph is just a little umph.", author: nil},
  %{
    body: "Strong people are harder to kill than weak people and more useful in general.",
    author: "Mark Rippetoe"
  },
  %{
    body: "Success usually comes to those who are too busy to be looking for it.",
    author: "Henry David Thoreau"
  },
  %{
    body: "The gym is the one place where you can be in complete control of your progress.",
    author: nil
  }
]

existing_count = Repo.aggregate(TrainingQuote, :count)

if existing_count == 0 do
  Enum.each(quotes, fn attrs ->
    %TrainingQuote{} |> TrainingQuote.changeset(attrs) |> Repo.insert!()
  end)

  IO.puts("Seeded #{length(quotes)} training quotes.")
end

# Scale levels are tenant-owned (ADR-128): each organization gets the default
# set when it is provisioned, and existing organizations were backfilled by
# the 20261012160000 migration. Re-assert the defaults for any organization
# that has none (idempotent).
for organization <- Repo.all(Palee.Organizations.Organization) do
  {:ok, _levels} = Workouts.seed_default_scale_levels(%{organization_id: organization.id})
end

# Registration requires an email (invitation email binding, F-10).
ensure_admin = fn admin_nickname, admin_password, admin_email ->
  admin =
    case Identity.find_by_nickname(admin_nickname) do
      nil ->
        {:ok, user} =
          Identity.register(%{
            nickname: admin_nickname,
            email: admin_email,
            password: admin_password,
            email: admin_email,
            role: :member
          })

        {:ok, admin_user} = Identity.update_role(user, :admin)
        admin_user

      %{role: :admin} = user ->
        {:ok, updated_user} = Identity.update_profile(user.id, %{password: admin_password})
        updated_user

      user ->
        {:ok, updated_user} = Identity.update_profile(user.id, %{password: admin_password})
        {:ok, admin_user} = Identity.update_role(updated_user, :admin)
        admin_user
    end

  IO.puts("Ensured #{Mix.env()} admin account: #{admin.nickname}")
  admin
end

# Tenant admins need an organization membership: membershipless non-vendor
# accounts cannot reach any tenant surface (ADR-091/ADR-095). Dev only; in
# production organizations are provisioned by a vendor (ADR-092).
ensure_dev_organization = fn admin, name ->
  organization =
    case Organizations.get_by_slug(System.get_env("DEV_ORGANIZATION_SLUG", "demo-gym")) do
      nil ->
        {:ok, organization} = Organizations.create_organization(%{name: name})
        organization

      organization ->
        organization
    end

  {:ok, _membership} =
    Organizations.add_membership(%{
      organization_id: organization.id,
      user_id: admin.id,
      role: :owner,
      status: :active,
      joined_at: DateTime.utc_now()
    })

  IO.puts("Ensured dev organization: #{organization.name} (/org/#{organization.slug}/admin)")
end

case Mix.env() do
  :dev ->
    admin_nickname = System.get_env("DEV_ADMIN_NICKNAME", "admin")
    admin_password = System.get_env("DEV_ADMIN_PASSWORD", "AdminPass123!")
    admin_email = System.get_env("DEV_ADMIN_EMAIL", "admin@example.com")

    admin_nickname
    |> ensure_admin.(admin_password, admin_email)
    |> ensure_dev_organization.(System.get_env("DEV_ORGANIZATION_NAME", "Demo Gym"))

  :prod ->
    admin_nickname = System.get_env("PROD_ADMIN_NICKNAME", "xristoforos_coach")
    admin_password = System.get_env("PROD_ADMIN_PASSWORD", "ChangeMeProdAdmin123!")
    admin_email = System.get_env("PROD_ADMIN_EMAIL") || raise("PROD_ADMIN_EMAIL is required")

    ensure_admin.(admin_nickname, admin_password, admin_email)

  _env ->
    :ok
end
