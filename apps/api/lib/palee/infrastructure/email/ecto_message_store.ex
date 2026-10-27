defmodule Palee.Infrastructure.Email.EctoMessageStore do
  @moduledoc """
  Ecto adapter of the outbox and the suppression list (ADR-203).

  `insert_with_job/2` inserts the message with `ON CONFLICT DO NOTHING` on
  its idempotency key and its Oban job in the same transaction (joining the
  caller's, when there is one), so a message never exists without its job
  and a duplicate request never aborts the caller's transaction with a
  unique violation.
  """

  @behaviour Palee.Email.Ports.MessageStore

  import Ecto.Query

  alias Palee.Email.{Message, Suppression}
  alias Palee.Repo

  @filters ~w(kind to_address status category organization_id user_id login_id idempotency_key)a

  @impl true
  def insert_with_job(attrs, job) do
    changeset = Message.create_changeset(attrs)

    if changeset.valid? do
      Repo.transaction(fn ->
        message =
          changeset
          |> Repo.insert(on_conflict: :nothing, conflict_target: :idempotency_key)
          |> or_rollback()

        case existing(message) do
          nil ->
            message |> job.() |> Repo.insert() |> or_rollback()
            message

          existing ->
            existing
        end
      end)
    else
      {:error, changeset}
    end
  end

  # With a key, the row that holds it: another request's when ours was skipped.
  defp existing(%Message{idempotency_key: nil}), do: nil

  defp existing(%Message{idempotency_key: key, id: id}) do
    case get_by_idempotency_key(key) do
      %Message{id: ^id} -> nil
      other -> other
    end
  end

  defp or_rollback({:ok, value}), do: value
  defp or_rollback({:error, reason}), do: Repo.rollback(reason)

  @impl true
  def get(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Message, uuid)
      :error -> nil
    end
  end

  @impl true
  def get_by_idempotency_key(key) when is_binary(key),
    do: Repo.get_by(Message, idempotency_key: key)

  @impl true
  def list_by_idempotency_prefix(prefix) when is_binary(prefix) and prefix != "" do
    pattern = escape_like(prefix) <> "%"

    Message
    |> where([m], like(m.idempotency_key, ^pattern))
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> Repo.all()
  end

  @impl true
  def list(filters) do
    filters
    |> Keyword.take(@filters)
    |> Enum.reduce(Message, fn {field, value}, query ->
      where(query, [m], field(m, ^field) == ^value)
    end)
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> Repo.all()
  end

  @impl true
  def update(%Message{} = message, fields),
    do: message |> Ecto.Changeset.change(fields) |> Repo.update()

  @impl true
  def count_sent_since(%DateTime{} = since) do
    Message
    |> where([m], m.status == "sent" and m.sent_at >= ^since)
    |> Repo.aggregate(:count)
  end

  @impl true
  def recent_to(address, kind, %DateTime{} = since) do
    [count, last_at] =
      Message
      |> where([m], m.to_address == ^address and m.kind == ^kind and m.inserted_at >= ^since)
      |> where([m], m.status not in ["failed", "suppressed"])
      |> select([m], [count(m.id), max(m.inserted_at)])
      |> Repo.one()

    %{count: count, last_at: last_at}
  end

  @impl true
  def suppressed?(digest) when is_binary(digest),
    do: Repo.exists?(from(s in Suppression, where: s.address_digest == ^digest))

  @impl true
  def suppress(digest, reason) when is_binary(digest) do
    %Suppression{address_digest: digest, reason: reason}
    |> Repo.insert(
      on_conflict: [set: [reason: reason]],
      conflict_target: :address_digest,
      returning: true
    )
  end

  @impl true
  def unsuppress(digest) when is_binary(digest) do
    Repo.delete_all(from(s in Suppression, where: s.address_digest == ^digest))
    :ok
  end

  defp escape_like(value), do: String.replace(value, ~r/([\\%_])/, "\\\\\\1")
end
