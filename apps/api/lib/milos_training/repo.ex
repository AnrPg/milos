defmodule MilosTraining.Repo do
  use Ecto.Repo,
    otp_app: :milos_training,
    adapter: Ecto.Adapters.Postgres
end
