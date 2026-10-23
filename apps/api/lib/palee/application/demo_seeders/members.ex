defmodule Palee.Application.DemoSeeders.Members do
  @moduledoc """
  ADR-184: mock members and athletes for the members screen.

  Each mock person is an account no one can use: a nickname ending in
  `_demo_<hex>` (so it reads as demo wherever it shows), a random password
  that is never stored or shown and an `.invalid` address (RFC 2606) no mail
  is ever delivered to. The profile is marked with the business
  (`users.demo_organization_id`), so no discovery path outside it ever lists
  them (ADR-184 follow-up «Mock people stay private»). Their memberships are added without announcing
  `:membership_activated`, so no referral, trial or event reaction runs.
  """

  @behaviour Palee.Application.DemoSeeder

  alias Palee.{Identity, Organizations}

  @people [
    {"Maria", :member},
    {"Nikos", :member},
    {"Eleni", :member},
    {"Giorgos", :member},
    {"Katerina", :member},
    {"Dimitris", :athlete},
    {"Sofia", :athlete},
    {"Kostas", :member}
  ]

  @impl true
  def section, do: "members"

  @impl true
  def requires, do: []

  @impl true
  def sources, do: ["users", "organization_memberships"]

  @impl true
  def seed(context, _seeded, now) do
    Enum.reduce_while(@people, {:ok, []}, fn {name, role}, {:ok, rows} ->
      with {:ok, user} <-
             Identity.register_demo_person(context.organization_id, account_params(name, role)),
           {:ok, membership} <-
             Organizations.add_demo_membership(context, %{
               user_id: user.id,
               role: role,
               roles: [role],
               status: :active,
               joined_at: DateTime.add(now, -Enum.random(7..200) * 86_400, :second)
             }) do
        {:cont, {:ok, rows ++ [{"users", user.id}, {"organization_memberships", membership.id}]}}
      else
        error -> {:halt, error}
      end
    end)
  end

  @doc "Whether a nickname is one this seeder made (for display and tests)."
  def mock_nickname?(nickname) when is_binary(nickname),
    do: Regex.match?(~r/_demo_[0-9a-f]{6}$/, nickname)

  def mock_nickname?(_nickname), do: false

  defp account_params(name, role) do
    suffix = :crypto.strong_rand_bytes(3) |> Base.encode16(case: :lower)

    %{
      nickname: "#{name}_demo_#{suffix}",
      password: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false),
      role: role,
      email: "demo-#{Ecto.UUID.generate()}@demo.palee.invalid"
    }
  end
end
