defmodule Palee.Organizations.Domain.BrandLogoPolicy do
  @moduledoc """
  Pure rules for first-class tenant logo uploads (ADR-121).

  Logos live under `organizations/<organization_id>/branding/logo/<uuid>.<ext>`
  in the public media bucket. Only raster formats that browsers cannot execute
  are accepted - PNG, JPEG and WebP - and the stored bytes, not the
  client-declared type, decide: the magic-byte probe must match both an
  allowed type and the extension baked into the object key. SVG is rejected
  outright because it can carry script and there is no safe sanitizer in the
  dependency set.
  """

  alias Palee.Organizations.{PlatformContext, TenantContext}

  @max_bytes 2 * 1_024 * 1_024
  @probe_bytes 16
  @content_types %{"image/png" => "png", "image/jpeg" => "jpg", "image/webp" => "webp"}
  @administering_roles [:owner, :admin]

  @type actor :: %{
          organization_id: Ecto.UUID.t(),
          user_id: Ecto.UUID.t(),
          scope: :tenant | :vendor
        }

  def max_bytes, do: @max_bytes
  def probe_bytes, do: @probe_bytes
  def allowed_content_types, do: Map.keys(@content_types) |> Enum.sort()

  @doc """
  Resolves who is changing which organization's logo. Tenant owners/admins may
  only act on their own organization; vendors act on the organization named
  by the platform route.
  """
  @spec authorize(term(), term()) :: {:ok, actor()} | {:error, atom()}
  def authorize(%TenantContext{role: role} = context, organization_id)
      when role in @administering_roles do
    if is_nil(organization_id) or organization_id == context.organization_id,
      do:
        {:ok,
         %{organization_id: context.organization_id, user_id: context.user_id, scope: :tenant}},
      else: {:error, :forbidden}
  end

  def authorize(%TenantContext{}, _organization_id), do: {:error, :forbidden}

  def authorize(%PlatformContext{user_id: user_id}, organization_id)
      when is_binary(organization_id) and organization_id != "" do
    case Ecto.UUID.cast(organization_id) do
      {:ok, organization_id} ->
        {:ok, %{organization_id: organization_id, user_id: user_id, scope: :vendor}}

      :error ->
        {:error, :not_found}
    end
  end

  def authorize(%PlatformContext{}, _organization_id), do: {:error, :not_found}
  def authorize(_context, _organization_id), do: {:error, :organization_context_required}

  @doc "Validates a client's upload request before a presigned URL is issued."
  @spec validate_request(term(), term()) ::
          {:ok, String.t()} | {:error, :invalid_brand_logo_upload}
  def validate_request(content_type, byte_size)
      when is_binary(content_type) and is_integer(byte_size) and byte_size > 0 and
             byte_size <= @max_bytes do
    if Map.has_key?(@content_types, content_type),
      do: {:ok, content_type},
      else: {:error, :invalid_brand_logo_upload}
  end

  def validate_request(_content_type, _byte_size), do: {:error, :invalid_brand_logo_upload}

  @doc "Tenant-owned key prefix every logo object for the organization lives under."
  def key_prefix(organization_id) when is_binary(organization_id),
    do: "organizations/#{organization_id}/branding/logo/"

  @doc "A fresh object key for a validated content type."
  def object_key(organization_id, object_id, content_type)
      when is_binary(organization_id) and is_binary(object_id) do
    key_prefix(organization_id) <> object_id <> "." <> Map.fetch!(@content_types, content_type)
  end

  @doc """
  True only for a key this policy would have issued for the organization:
  exact prefix, a UUID file name, an allowed extension, no traversal.
  """
  def owned_key?(organization_id, key) when is_binary(organization_id) and is_binary(key) do
    prefix = key_prefix(organization_id)

    with true <- String.starts_with?(key, prefix),
         file_name = binary_part(key, byte_size(prefix), byte_size(key) - byte_size(prefix)),
         [object_id, extension] <- String.split(file_name, ".", parts: 2),
         {:ok, _uuid} <- Ecto.UUID.cast(object_id) do
      extension in Map.values(@content_types)
    else
      _other -> false
    end
  end

  def owned_key?(_organization_id, _key), do: false

  @doc """
  Validates the stored object: non-empty, within the size limit, and its magic
  bytes identify an allowed image type matching the key's extension.
  """
  @spec validate_object(String.t(), %{head: binary(), byte_size: term()}) ::
          {:ok, String.t()} | {:error, term()}
  def validate_object(key, %{head: head, byte_size: byte_size}) when is_binary(head) do
    detected = detect_type(head)

    cond do
      not is_integer(byte_size) or byte_size <= 0 ->
        {:error, :brand_logo_upload_missing}

      byte_size > @max_bytes ->
        {:error, {:brand_logo_too_large, byte_size}}

      is_nil(detected) ->
        {:error, :unsupported_brand_logo_type}

      Path.extname(key) != "." <> Map.fetch!(@content_types, detected) ->
        {:error, :unsupported_brand_logo_type}

      true ->
        {:ok, detected}
    end
  end

  def validate_object(_key, _object), do: {:error, :brand_logo_upload_missing}

  @doc "Identifies an allowed image type from its leading bytes."
  def detect_type(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>>), do: "image/png"
  def detect_type(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: "image/jpeg"

  def detect_type(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>),
    do: "image/webp"

  def detect_type(_head), do: nil

  @doc """
  The audit event a logo change produces, or nil when nothing changes.
  `current` is the settings row before the change; `next_key` is the new
  object key (nil for removal).
  """
  def change_event(%{brand_logo_object_key: key}, key) when is_binary(key), do: nil
  def change_event(%{brand_logo_object_key: nil, brand_logo_url: nil}, nil), do: nil
  def change_event(_current, nil), do: "organization_logo_removed"

  def change_event(%{brand_logo_object_key: nil, brand_logo_url: nil}, _key),
    do: "organization_logo_uploaded"

  def change_event(_current, _key), do: "organization_logo_replaced"

  @doc "Audit metadata: ids, keys and timestamps only - no personal data."
  def event_metadata(actor, current, next_key, %DateTime{} = changed_at) do
    %{
      actor_scope: Atom.to_string(actor.scope),
      object_key: next_key,
      previous_object_key: current.brand_logo_object_key,
      previous_external_url:
        is_nil(current.brand_logo_object_key) and not is_nil(current.brand_logo_url),
      changed_at: DateTime.to_iso8601(changed_at)
    }
  end

  @doc """
  The superseded object to delete after a change, only if it is a key this
  policy issued for the same organization (never an arbitrary key).
  """
  def superseded_key(organization_id, previous_key, next_key) do
    if is_binary(previous_key) and previous_key != next_key and
         owned_key?(organization_id, previous_key),
       do: previous_key
  end
end
