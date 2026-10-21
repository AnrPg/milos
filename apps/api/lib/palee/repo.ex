defmodule Palee.Repo do
  use Ecto.Repo,
    otp_app: :palee,
    adapter: Ecto.Adapters.Postgres
end
