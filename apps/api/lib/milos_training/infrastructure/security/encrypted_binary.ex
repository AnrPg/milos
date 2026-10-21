defmodule MilosTraining.Infrastructure.Security.EncryptedBinary do
  @moduledoc """
  An Ecto type that keeps a secret encrypted in the database and plain in
  memory (`DataCipher`, ADR-161). A value that no longer decrypts (a changed
  key) loads as `nil`, which callers treat as «reconnect».
  """

  use Ecto.Type

  alias MilosTraining.Infrastructure.Security.DataCipher

  @impl true
  def type, do: :binary

  @impl true
  def cast(nil), do: {:ok, nil}
  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(_value), do: :error

  @impl true
  def dump(nil), do: {:ok, nil}
  def dump(value) when is_binary(value), do: {:ok, DataCipher.encrypt(value)}
  def dump(_value), do: :error

  @impl true
  def load(nil), do: {:ok, nil}

  def load(value) when is_binary(value) do
    case DataCipher.decrypt(value) do
      {:ok, plaintext} -> {:ok, plaintext}
      {:error, _reason} -> {:ok, nil}
    end
  end

  @impl true
  def equal?(a, b), do: a == b
end
