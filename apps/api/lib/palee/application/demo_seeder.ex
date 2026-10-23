defmodule Palee.Application.DemoSeeder do
  @moduledoc """
  ADR-184: one section's demo seeder. A seeder fills one admin screen of a
  demo business with ordinary rows written through the owning contexts'
  public APIs, and returns every row it wrote as `{table, id}` so
  `Application.DemoData` can track them and activation can delete exactly
  those.

  Rules every seeder follows:

  - it writes only tables listed in `sources/0`, which must all be deletable
    (`BusinessAccounts.demo_deletable_sources/0`) or `"users"`;
  - mock people are created only by the `members` seeder: accounts with an
    unusable random password and an `.invalid` address, so they can never
    sign in or be emailed, and tracked so they never get a notification;
  - it never calls an application service that notifies, announces a domain
    event or goes live (no invitations, no `SubmitBooking`);
  - it reads the rows of the sections it `requires/0` from `seeded`.

  Add a section by writing a module and listing it in
  `Application.DemoSeeders`.
  """

  @type row :: {String.t(), Ecto.UUID.t()}
  @type seeded :: %{optional(String.t()) => [row()]}

  @doc "The section key, as the web names the screen (`members`, `schedule`, ...)."
  @callback section() :: String.t()

  @doc "Sections whose rows this one builds on; seeded first when missing."
  @callback requires() :: [String.t()]

  @doc "The tables this seeder writes."
  @callback sources() :: [String.t()]

  @doc "Writes the section's mock data in the demo business's tenant context."
  @callback seed(context :: map(), seeded(), now :: DateTime.t()) ::
              {:ok, [row()]} | {:error, term()}
end
