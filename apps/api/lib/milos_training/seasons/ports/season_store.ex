defmodule MilosTraining.Seasons.Ports.SeasonStore do
  @moduledoc """
  Persistence port for season offerings and enrollments (ADR-167). Every call
  runs in the caller's `RepoContext`, always the gym's scope.
  """

  alias MilosTraining.Seasons.{SeasonEnrollment, SeasonOffering}

  @type context :: map()
  @type id :: binary()

  @callback create_offering(context(), map()) ::
              {:ok, SeasonOffering.t()} | {:error, Ecto.Changeset.t()}
  @callback update_offering(context(), SeasonOffering.t(), map()) ::
              {:ok, SeasonOffering.t()} | {:error, Ecto.Changeset.t()}
  @callback get_offering(context(), id()) :: SeasonOffering.t() | nil

  @doc "The gym's offerings, optionally only those in `statuses`, newest start first."
  @callback list_offerings(context(), %{optional(:statuses) => [String.t()]}) ::
              [SeasonOffering.t()]

  @doc "Enrollment counts per offering and status."
  @callback enrollment_counts(context(), [id()]) :: %{
              id() => %{String.t() => non_neg_integer()}
            }

  @doc "Titles of offerings by id (labels for assigned workouts)."
  @callback titles(context(), [id()]) :: %{id() => String.t()}

  @doc "The season of each of these assigned workouts that belongs to one (journal labels)."
  @callback assignment_seasons(context(), [id()]) :: %{id() => %{id: id(), title: String.t()}}

  @callback get_enrollment(context(), id()) :: SeasonEnrollment.t() | nil
  @callback get_member_enrollment(context(), id(), id()) :: SeasonEnrollment.t() | nil

  @doc "An offering's enrollments, oldest request first."
  @callback list_enrollments(context(), id()) :: [SeasonEnrollment.t()]

  @doc "A member's enrollments at the gym."
  @callback list_member_enrollments(context(), id()) :: [SeasonEnrollment.t()]

  @callback insert_enrollment(context(), map()) ::
              {:ok, SeasonEnrollment.t()} | {:error, Ecto.Changeset.t()}
  @callback update_enrollment(context(), SeasonEnrollment.t(), map()) ::
              {:ok, SeasonEnrollment.t()} | {:error, Ecto.Changeset.t()}

  @doc "The earliest waitlisted enrollment of an offering, or nil."
  @callback first_waitlisted(context(), id()) :: SeasonEnrollment.t() | nil

  @doc "Runs `fun` in one transaction holding the offering's lock (places stay exact)."
  @callback with_offering_lock(context(), id(), (-> result)) :: result when result: term()
end
