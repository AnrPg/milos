defmodule MilosTraining.Application.PublicURL do
  def base_url, do: Application.fetch_env!(:milos_training, :public_base_url)
end
