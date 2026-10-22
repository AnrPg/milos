defmodule Palee.Workouts.WorkoutSection do
  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Execution.Domain.TimerPresets

  alias Palee.Workouts.Domain.{
    SectionedText,
    TimerConfig,
    WorkoutAuthoringMetadata,
    WorkoutContent
  }

  alias Palee.Workouts.{MasterWorkout, WorkoutExercise}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "workout_sections" do
    field :organization_id, :binary_id
    field :name, :string
    field :order, :integer
    field :scoreable, :boolean, default: false
    field :score_config, :map
    field :timer_config, :map
    field :note, :string
    field :subtitle, :string
    field :rest_before_next_section_seconds, :integer
    field :content, {:array, :map}, default: []
    field :section_metadata, :map, default: %{}
    # ADR-180: a text section of a workout written without the assistant.
    field :free_text_body, :string
    field :free_text_document, :map
    field :timer_preset, :map

    belongs_to :master_workout, MasterWorkout
    belongs_to :parent_section, __MODULE__
    has_many :exercises, WorkoutExercise, preload_order: [asc: :order]

    timestamps()
  end

  def changeset(section \\ %__MODULE__{}, params) do
    section
    |> base_changeset(params)
    |> cast_assoc(:exercises, required: true, with: &WorkoutExercise.changeset/2)
  end

  def persist_changeset(section \\ %__MODULE__{}, params) do
    section
    |> base_changeset(params)
  end

  defp base_changeset(section, params) do
    section
    |> cast(params, [
      :master_workout_id,
      :name,
      :order,
      :scoreable,
      :score_config,
      :timer_config,
      :parent_section_id,
      :note,
      :subtitle,
      :rest_before_next_section_seconds,
      :content,
      :section_metadata,
      :free_text_body,
      :free_text_document,
      :timer_preset
    ])
    |> update_change(:name, &normalize_name/1)
    |> validate_required([:name, :order])
    |> validate_number(:order, greater_than_or_equal_to: 1)
    |> validate_length(:subtitle, max: 240)
    |> validate_number(:rest_before_next_section_seconds, greater_than_or_equal_to: 0)
    |> validate_length(:free_text_body, max: SectionedText.max_body_bytes(), count: :bytes)
    |> normalize_timer_preset()
    |> validate_bounded_metadata()
    |> validate_content()
    |> normalize_timer_config()
    |> foreign_key_constraint(:master_workout_id)
    |> foreign_key_constraint(:parent_section_id,
      name: :workout_sections_parent_same_workout_fkey
    )
    |> unique_constraint(:order, name: :workout_sections_root_order_index)
    |> unique_constraint(:order, name: :workout_sections_child_order_index)
  end

  defp normalize_name(nil), do: nil
  defp normalize_name(name), do: String.trim(name)

  defp normalize_timer_config(changeset) do
    case fetch_change(changeset, :timer_config) do
      {:ok, timer_config} ->
        case TimerConfig.normalize(timer_config) do
          {:ok, normalized} -> put_change(changeset, :timer_config, normalized)
          {:error, reason} -> add_error(changeset, :timer_config, reason)
        end

      :error ->
        changeset
    end
  end

  defp normalize_timer_preset(changeset) do
    case fetch_change(changeset, :timer_preset) do
      {:ok, nil} ->
        changeset

      {:ok, preset} ->
        case TimerPresets.parse(preset) do
          nil -> add_error(changeset, :timer_preset, "has an unsupported format")
          parsed -> put_change(changeset, :timer_preset, parsed)
        end

      :error ->
        changeset
    end
  end

  defp validate_bounded_metadata(changeset) do
    validate_change(changeset, :section_metadata, fn :section_metadata, metadata ->
      case WorkoutAuthoringMetadata.validate(:section, metadata) do
        :ok -> []
        {:error, reason} -> [section_metadata: "is invalid: #{inspect(reason)}"]
      end
    end)
  end

  defp validate_content(changeset) do
    level = :section

    validate_change(changeset, :content, fn :content, content ->
      case WorkoutContent.validate(content, level) do
        :ok -> []
        {:error, reason} -> [content: "is invalid: #{inspect(reason)}"]
      end
    end)
  end
end
