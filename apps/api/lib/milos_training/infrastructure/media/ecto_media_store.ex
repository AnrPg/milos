defmodule MilosTraining.Infrastructure.Media.EctoMediaStore do
  @moduledoc "Ecto adapter of the Media store (ADR-148, ADR-157)."

  @behaviour MilosTraining.Media.Ports.MediaStore

  import Ecto.Query

  alias MilosTraining.Media.{AccountObject, TenantObject}
  alias MilosTraining.Repo

  @impl true
  def create(%{organization_id: organization_id} = context, :tenant, attrs) do
    attrs
    |> Map.merge(%{organization_id: organization_id, uploaded_by_id: Map.get(context, :user_id)})
    |> TenantObject.create_changeset()
    |> Repo.insert()
    |> normalize_result()
  end

  def create(%{user_id: user_id}, :account, attrs) do
    attrs
    |> Map.put(:user_id, user_id)
    |> AccountObject.create_changeset()
    |> Repo.insert()
    |> normalize_result()
  end

  @impl true
  def get(context, scope, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> context |> owned(scope) |> where([m], m.id == ^id) |> Repo.one() |> normalize()
      :error -> nil
    end
  end

  @impl true
  def list(context, scope, ids) do
    ids = for id <- ids, {:ok, id} <- [Ecto.UUID.cast(id)], do: id

    context
    |> owned(scope)
    |> where([m], m.id in ^ids)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def mark_ready(context, scope, id, attrs) do
    {count, rows} =
      context
      |> owned(scope)
      |> where([m], m.id == ^id and m.status == "pending")
      |> select([m], m)
      |> Repo.update_all(
        set: [
          status: "ready",
          byte_size: attrs.byte_size,
          width: attrs.width,
          height: attrs.height,
          updated_at: DateTime.utc_now()
        ]
      )

    case {count, rows} do
      {1, [row]} -> {:ok, normalize(row)}
      _none -> {:error, :media_not_found}
    end
  end

  @impl true
  def mark_processing(context, scope, id, attrs) do
    transition(context, scope, id, ["pending"],
      status: "processing",
      byte_size: attrs.byte_size,
      content_type: attrs.content_type
    )
  end

  @impl true
  def mark_processed(context, scope, id, attrs) do
    transition(context, scope, id, ["processing"],
      status: "ready",
      width: attrs.width,
      height: attrs.height,
      byte_size: attrs.byte_size,
      content_type: attrs.content_type,
      variants: attrs.variants,
      placeholder: attrs.placeholder,
      duration_ms: Map.get(attrs, :duration_ms)
    )
  end

  @impl true
  def mark_rejected(context, scope, id, reason) do
    transition(context, scope, id, ["pending", "processing"],
      status: "rejected",
      rejection_reason: to_string(reason)
    )
  end

  defp transition(context, scope, id, from, changes) do
    {count, rows} =
      context
      |> owned(scope)
      |> where([m], m.id == ^id and m.status in ^from)
      |> select([m], m)
      |> Repo.update_all(set: Keyword.put(changes, :updated_at, DateTime.utc_now()))

    case {count, rows} do
      {1, [row]} -> {:ok, normalize(row)}
      _none -> {:error, :media_not_found}
    end
  end

  @impl true
  def attach(_context, _scope, [], _attachment, _at), do: {:ok, 0}

  def attach(context, scope, ids, attachment, at) do
    {count, _rows} =
      context
      |> owned(scope)
      |> where([m], m.id in ^ids and is_nil(m.attached_at) and m.status != "rejected")
      |> Repo.update_all(
        set: [
          attached_at: at,
          attached_type: attachment.type,
          attached_id: attachment.id,
          attached_organization_id: Map.get(attachment, :organization_id),
          updated_at: DateTime.utc_now()
        ]
      )

    {:ok, count}
  end

  @impl true
  def update_alt_text(context, scope, id, text) do
    {count, rows} =
      context
      |> owned(scope)
      |> where([m], m.id == ^id and m.status != "rejected")
      |> select([m], m)
      |> Repo.update_all(set: [alt_text: text, updated_at: DateTime.utc_now()])

    case {count, rows} do
      {1, [row]} -> {:ok, normalize(row)}
      _none -> {:error, :media_not_found}
    end
  end

  @impl true
  def usage(context, scope, since) do
    query = owned(context, scope)

    open =
      query
      |> where([m], is_nil(m.attached_at) and m.inserted_at >= ^since)
      |> Repo.aggregate(:count)

    bytes =
      query
      |> where([m], m.status == "ready")
      |> select([m], coalesce(sum(m.byte_size), 0))
      |> Repo.one()

    %{open_uploads: open, bytes: to_integer(bytes)}
  end

  defp to_integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(_value), do: 0

  @impl true
  def set_attached(_context, _scope, [], _at), do: :ok

  def set_attached(context, scope, ids, at) do
    context
    |> owned(scope)
    |> where([m], m.id in ^ids)
    |> Repo.update_all(set: [attached_at: at, updated_at: DateTime.utc_now()])

    :ok
  end

  @impl true
  def delete(_context, _scope, []), do: {:ok, []}

  def delete(context, scope, ids) do
    {_count, rows} =
      context
      |> owned(scope)
      |> where([m], m.id in ^ids)
      |> select([m], m)
      |> Repo.delete_all()

    {:ok, Enum.map(rows, &normalize/1)}
  end

  @impl true
  def list_unattached(context, scope, before) do
    context
    |> owned(scope)
    |> where([m], is_nil(m.attached_at) and m.inserted_at < ^before)
    |> limit(500)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def list_ids_by_purpose(context, scope, purpose) do
    context
    |> owned(scope)
    |> where([m], m.purpose == ^purpose)
    |> select([m], m.id)
    |> Repo.all()
  end

  @impl true
  def account_orphan_owner_ids(before) do
    %{rows: rows} =
      Repo.query!("SELECT id FROM milos_account_media_orphan_owner_ids($1) AS id", [before])

    Enum.map(rows, fn [id] -> Ecto.UUID.load!(id) end)
  end

  @impl true
  def dangling_post_media(before, limit),
    do: owner_media_pairs("milos_dangling_post_media", before, limit)

  @impl true
  def stale_post_media(before, limit),
    do: owner_media_pairs("milos_stale_post_media", before, limit)

  defp owner_media_pairs(function, before, limit) do
    %{rows: rows} =
      Repo.query!("SELECT user_id, media_id FROM #{function}($1, $2)", [before, limit])

    Enum.map(rows, fn [user_id, media_id] ->
      {Ecto.UUID.load!(user_id), Ecto.UUID.load!(media_id)}
    end)
  end

  defp owned(%{organization_id: organization_id}, :tenant),
    do: where(TenantObject, [m], m.organization_id == ^organization_id)

  defp owned(%{user_id: user_id}, :account),
    do: where(AccountObject, [m], m.user_id == ^user_id)

  defp normalize_result({:ok, row}), do: {:ok, normalize(row)}
  defp normalize_result({:error, changeset}), do: {:error, changeset}

  defp normalize(nil), do: nil

  defp normalize(%TenantObject{} = m),
    do: m |> base() |> Map.merge(%{scope: :tenant, owner_id: m.organization_id})

  defp normalize(%AccountObject{} = m),
    do: m |> base() |> Map.merge(%{scope: :account, owner_id: m.user_id})

  defp base(m) do
    %{
      id: m.id,
      purpose: m.purpose,
      object_key: m.object_key,
      content_type: m.content_type,
      byte_size: m.byte_size,
      width: m.width,
      height: m.height,
      status: m.status,
      attached_at: m.attached_at,
      inserted_at: m.inserted_at,
      updated_at: m.updated_at,
      variants: m.variants || %{},
      placeholder: m.placeholder,
      alt_text: m.alt_text,
      duration_ms: m.duration_ms,
      rejection_reason: m.rejection_reason,
      attached_type: m.attached_type,
      attached_id: m.attached_id,
      attached_organization_id: m.attached_organization_id
    }
  end
end
