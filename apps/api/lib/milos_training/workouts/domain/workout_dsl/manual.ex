defmodule MilosTraining.Workouts.Domain.WorkoutDsl.Manual do
  @moduledoc """
  Generates the in-app Quick Text reference from the canonical registry.
  """

  alias MilosTraining.Workouts.Domain.WorkoutDsl.{Templates, Vocabulary}

  def export do
    %{
      version: 1,
      markdown: markdown(),
      templates: Templates.export(),
      vocabulary: Vocabulary.export()
    }
  end

  def markdown do
    """
    # Quick Text workout DSL — Coach manual

    Quick Text is a document-like authoring mode, not a second workout model.
    The text is parsed into the same canonical workout used by Structured mode.
    Invalid text remains safely autosaved, but Preview, conversion and Publish
    require zero errors. Warnings must be reviewed and explicitly accepted.

    ## The few rules

    - A complete document starts with `[workout]` and ends with `[/workout]`.
    - A block starts with `[kind]` or `[kind: value]` and closes with `[/kind]`.
    - Parameters use `canonical-key: value`, one per line.
    - Blank lines are only visual spacing. Canonical Beautify controls ordering.
    - Names and prose may contain spaces. Structural keywords are the exact
      lowercase kebab-case words offered by autocomplete.
    - Duration values use `s`, `m`, or `h`; loads use `kg`, `lb`, `%1rm`, or
      `bw`; distances use `m` or `km`.
    - Exercise names must match a canonical catalog name or exact registered
      alias. Autocomplete is the safest way to enter them.
    - Notes use typed markers: #{Enum.join(Vocabulary.note_markers(), ", ")}.
      Coach-only notes are never exposed in athlete-facing workout responses.

    ## Nesting

    Workout may contain sections. Sections may contain headers, exercises,
    composition groups, and nested sections. Exercises may contain scale
    blocks. Blocks must close in reverse order. A header is presentation only;
    it is never treated as an executable exercise.

    ## Prescriptions and progression

    Uniform work uses `sets`, one dimension such as `reps`, `duration`,
    `calories`, or `distance`, and optional `load`.

    Linear load uses:

    ```text
    progression: linear
    sets: 5
    reps: 5
    load-start: 60kg
    load-step: +5kg
    ```

    Use a negative step for deload. Arbitrary per-set work uses
    `progression: explicit`, followed by `sets:` and canonical `- ...` set
    lines. Each set may carry its own prescription, load, tempo, effort target,
    rest, and note.

    ## Composition and scaling

    `[group: superset]` and `[group: alternating]` contain two or more
    exercises. Group title, sets, rest and typed notes are canonical.
    `[scale: slug]` inside an exercise overrides or excludes that exercise for
    an active scale. Unknown scale slugs block publication.

    ## Rest

    Rest can be expressed at workout/section flow points, groups, exercises,
    sides, repetitions, clusters, sets, rounds, or as a dedicated
    `[section: rest]`. A rest section may use a fixed `duration` or a
    `recovery-condition`; conditional recovery creates a manual execution step.

    ## Section formats

    #{format_reference()}

    ## Canonicalization

    Beautify parses first and only rewrites valid text. It normalizes aliases,
    parameter order, units, spacing and block layout without changing canonical
    meaning. The backend reparses and preflights the exact source revision at
    Publish, then retains both canonical data and the recoverable source.
    """
    |> String.trim()
    |> Kernel.<>("\n")
  end

  defp format_reference do
    Vocabulary.section_formats()
    |> Enum.map_join("\n", fn format ->
      spec = Vocabulary.format_spec(format)
      required = names(spec.dsl_required)
      optional = names(spec.optional)
      scores = if spec.scores == [], do: "none", else: Enum.join(spec.scores, ", ")

      "- `#{Vocabulary.dsl_format(format)}` — body `#{spec.body}`; required: #{required}; optional: #{optional}; scores: #{scores}."
    end)
  end

  defp names([]), do: "none"

  defp names(fields) do
    fields
    |> Enum.map(&Vocabulary.dsl_key_for_timer_field/1)
    |> Enum.join(", ")
  end
end
