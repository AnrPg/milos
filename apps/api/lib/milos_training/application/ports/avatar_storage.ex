defmodule MilosTraining.Application.Ports.AvatarStorage do
  @callback create_upload(Ecto.UUID.t(), String.t(), pos_integer()) ::
              {:ok, map()} | {:error, term()}
  @callback validate_uploaded(Ecto.UUID.t(), String.t()) ::
              {:ok, String.t()} | {:error, term()}
end
