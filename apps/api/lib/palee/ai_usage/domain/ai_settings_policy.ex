defmodule Palee.AiUsage.Domain.AiSettingsPolicy do
  @moduledoc """
  Rules for a gym's AI settings (ADR-174), pure.

  * The key is write-only: `public/2` never includes it, only whether one is
    set, its last four characters and whether the provider rejected it.
  * A feature runs only when it is switched on, a key is set and the
    provider has not rejected that key (fail closed: no silent fallback to a
    platform key).
  * A new key resets the rejection; removing the key switches every feature
    off, so a gym never sees a feature «on» that cannot run.
  """

  @key_pattern ~r/^[A-Za-z0-9_\-]{20,300}$/
  @model_pattern ~r/^[a-z0-9][a-z0-9.\-]{2,79}$/

  @doc """
  Changes for an update request. Accepted keys: `scaling_enabled` and
  `voice_enabled` (booleans),
  `api_key` (string, replaces the key), `remove_key` (true), `model` (string,
  or nil/blank for the default). Returns `{:ok, changes}` or `{:error, reason}`.
  """
  def update_changes(current, params, actor_id) when is_map(params) do
    with {:ok, key_changes} <- key_changes(params),
         {:ok, model_changes} <- model_changes(params),
         {:ok, switch_changes} <- switch_changes(params) do
      changes =
        %{updated_by_id: actor_id}
        |> Map.merge(model_changes)
        |> Map.merge(switch_changes)
        |> Map.merge(key_changes)

      if switching_on_without_key?(current, changes),
        do: {:error, :api_key_required},
        else: {:ok, changes}
    end
  end

  def update_changes(_current, _params, _actor_id), do: {:error, :bad_request}

  defp key_changes(params) do
    cond do
      fetch(params, :remove_key) == true -> {:ok, removed_key()}
      true -> new_key(fetch(params, :api_key))
    end
  end

  defp new_key(:missing), do: {:ok, %{}}

  defp new_key(key) when is_binary(key) do
    key = String.trim(key)

    if Regex.match?(@key_pattern, key),
      do: {:ok, %{api_key: key, api_key_last4: String.slice(key, -4, 4), key_status: "unknown"}},
      else: {:error, :invalid_api_key}
  end

  defp new_key(_other), do: {:error, :invalid_api_key}

  defp removed_key,
    do: %{
      api_key: nil,
      api_key_last4: nil,
      key_status: "unknown",
      key_checked_at: nil,
      scaling_enabled: false,
      voice_enabled: false
    }

  defp model_changes(params) do
    case fetch(params, :model) do
      :missing -> {:ok, %{}}
      nil -> {:ok, %{model: nil}}
      model when is_binary(model) -> model |> String.trim() |> model_change()
      _other -> {:error, :invalid_model}
    end
  end

  defp model_change(""), do: {:ok, %{model: nil}}

  defp model_change(model) do
    if Regex.match?(@model_pattern, model),
      do: {:ok, %{model: model}},
      else: {:error, :invalid_model}
  end

  defp switch_changes(params) do
    with {:ok, scaling} <- switch_change(params, :scaling_enabled, :invalid_scaling_enabled),
         # ADR-175: voice logging has its own switch, off by default.
         {:ok, voice} <- switch_change(params, :voice_enabled, :invalid_voice_enabled) do
      {:ok, Map.merge(scaling, voice)}
    end
  end

  defp switch_change(params, field, error) do
    case fetch(params, field) do
      :missing -> {:ok, %{}}
      value when is_boolean(value) -> {:ok, %{field => value}}
      _other -> {:error, error}
    end
  end

  defp switching_on_without_key?(current, changes) do
    key = Map.get(changes, :api_key, value(current, :api_key, nil))

    Enum.any?([:scaling_enabled, :voice_enabled], fn field ->
      Map.get(changes, field, value(current, field, false)) == true
    end) and not present?(key)
  end

  @doc "Whether scaling suggestions may run for these settings."
  def scaling_ready?(%{scaling_enabled: true, api_key: key, key_status: status})
      when status != "rejected",
      do: present?(key)

  def scaling_ready?(_settings), do: false

  @doc "Whether voice logging may run for these settings (ADR-175)."
  def voice_ready?(%{voice_enabled: true, api_key: key, key_status: status})
      when status != "rejected",
      do: present?(key)

  def voice_ready?(_settings), do: false

  @doc "The model to call: the gym's override, else the platform default."
  def model(%{model: model}, _default) when is_binary(model) and model != "", do: model
  def model(_settings, default), do: default

  @doc "What the API may show: never the key itself."
  def public(settings, default_model) do
    %{
      provider: value(settings, :provider, "anthropic"),
      scaling_enabled: value(settings, :scaling_enabled, false),
      voice_enabled: value(settings, :voice_enabled, false),
      key_configured: present?(value(settings, :api_key, nil)),
      key_last4: value(settings, :api_key_last4, nil),
      key_status: value(settings, :key_status, "unknown"),
      model: value(settings, :model, nil),
      default_model: default_model
    }
  end

  defp value(nil, _key, default), do: default
  defp value(settings, key, default), do: Map.get(settings, key) || default

  defp fetch(params, key) do
    cond do
      Map.has_key?(params, key) -> Map.get(params, key)
      Map.has_key?(params, Atom.to_string(key)) -> Map.get(params, Atom.to_string(key))
      true -> :missing
    end
  end

  defp present?(value), do: is_binary(value) and value != ""
end
