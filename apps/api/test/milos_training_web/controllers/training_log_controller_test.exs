defmodule MilosTrainingWeb.TrainingLogControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Organizations, TestFixtures}

  defp organization_with_member(role \\ :member) do
    owner = TestFixtures.admin_fixture()

    member =
      TestFixtures.user_fixture(%{role: if(role == :athlete, do: :athlete, else: :member)})

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Log API Gym #{System.unique_integer([:positive])}"
      })

    for {user, membership_role} <- [{owner, :owner}, {member, role}] do
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: membership_role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    {organization, owner, member}
  end

  defp log_path(organization, suffix),
    do: "/api/org/#{organization.slug}/me/training-log#{suffix}"

  defp freeform_body(overrides \\ %{}) do
    Map.merge(
      %{
        source_type: "freeform",
        title: "Beach workout",
        performed_at: DateTime.utc_now() |> DateTime.add(-7200, :second) |> DateTime.to_iso8601(),
        timezone: "Europe/Athens",
        duration_seconds: 2400,
        perceived_effort: 7,
        notes: "Sand sprints",
        idempotency_key: "api-" <> Ecto.UUID.generate(),
        performed_exercises: [
          %{name: "Sprint", sets: 8, distance: 100, distance_unit: "m"},
          %{
            name: "Kettlebell swing",
            exercise_ref: "kb-swing",
            reps: 50,
            load: 24,
            load_unit: "kg"
          }
        ]
      },
      overrides
    )
  end

  test "member logs, lists, edits, and voids a freeform workout", %{conn: conn} do
    {organization, _owner, member} = organization_with_member()
    body = freeform_body()

    created =
      conn
      |> put_bearer_token(member)
      |> post(log_path(organization, "/entries"), body)
      |> json_response(201)

    entry = created["entry"]
    assert entry["source_type"] == "freeform"
    assert entry["status"] == "logged"
    assert entry["performed_at_tz"] == "Europe/Athens"
    assert [%{"name" => "Sprint"}, %{"exercise_ref" => "kb-swing"}] = entry["performed_exercises"]

    replay =
      build_conn()
      |> put_bearer_token(member)
      |> post(log_path(organization, "/entries"), body)
      |> json_response(200)

    assert replay["entry"]["id"] == entry["id"]

    listed =
      build_conn()
      |> put_bearer_token(member)
      |> get(log_path(organization, "/entries"))
      |> json_response(200)

    assert [%{"id" => id}] = listed["entries"]
    assert id == entry["id"]

    shown =
      build_conn()
      |> put_bearer_token(member)
      |> get(log_path(organization, "/entries/#{id}"))
      |> json_response(200)

    assert shown["entry"]["notes"] == "Sand sprints"

    updated =
      build_conn()
      |> put_bearer_token(member)
      |> patch(log_path(organization, "/entries/#{id}"), %{
        notes: "Sand sprints + swim",
        expected_version: entry["lock_version"]
      })
      |> json_response(200)

    assert updated["entry"]["notes"] == "Sand sprints + swim"

    stale =
      build_conn()
      |> put_bearer_token(member)
      |> patch(log_path(organization, "/entries/#{id}"), %{
        notes: "stale",
        expected_version: entry["lock_version"]
      })
      |> json_response(409)

    assert stale["code"] == "stale_training_log_entry"

    voided =
      build_conn()
      |> put_bearer_token(member)
      |> post(log_path(organization, "/entries/#{id}/void"), %{reason: "Logged twice"})
      |> json_response(200)

    assert voided["entry"]["status"] == "voided"
    assert voided["entry"]["void_reason"] == "Logged twice"

    frozen =
      build_conn()
      |> put_bearer_token(member)
      |> patch(log_path(organization, "/entries/#{id}"), %{notes: "after void"})
      |> json_response(409)

    assert frozen["code"] == "training_log_entry_voided"
  end

  test "sources endpoint returns the picker groups", %{conn: conn} do
    {organization, _owner, member} = organization_with_member()

    payload =
      conn
      |> put_bearer_token(member)
      |> get(log_path(organization, "/sources"))
      |> json_response(200)

    assert payload["classes"] == []
    assert payload["assignments"] == []
    assert is_list(payload["library_workouts"])
  end

  test "contract validation rejects unknown source types and missing idempotency keys",
       %{conn: conn} do
    {organization, _owner, member} = organization_with_member()

    conn
    |> put_bearer_token(member)
    |> post(log_path(organization, "/entries"), freeform_body(%{source_type: "timer"}))
    |> json_response(422)

    build_conn()
    |> put_bearer_token(member)
    |> post(log_path(organization, "/entries"), Map.delete(freeform_body(), :idempotency_key))
    |> json_response(422)
  end

  test "domain validation errors render as validation_failed", %{conn: conn} do
    {organization, _owner, member} = organization_with_member()

    future = DateTime.utc_now() |> DateTime.add(86_400, :second) |> DateTime.to_iso8601()

    payload =
      conn
      |> put_bearer_token(member)
      |> post(log_path(organization, "/entries"), freeform_body(%{performed_at: future}))
      |> json_response(422)

    assert payload["code"] == "validation_failed"
    assert payload["errors"]["performed_at_utc"]
  end

  test "athletes cannot log library workouts", %{conn: conn} do
    {organization, _owner, athlete} = organization_with_member(:athlete)

    payload =
      conn
      |> put_bearer_token(athlete)
      |> post(log_path(organization, "/entries"), %{
        source_type: "library_workout",
        source_reference_id: Ecto.UUID.generate(),
        performed_at: DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.to_iso8601(),
        idempotency_key: "api-" <> Ecto.UUID.generate()
      })
      |> json_response(403)

    assert payload["code"] == "training_log_source_forbidden"
  end

  test "entries are tenant scoped and owner scoped", %{conn: conn} do
    {organization, owner, member} = organization_with_member()
    {other_organization, _other_owner, _other_member} = organization_with_member()

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: other_organization.id,
        user_id: member.id,
        role: :member,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    entry =
      conn
      |> put_bearer_token(member)
      |> post(log_path(organization, "/entries"), freeform_body())
      |> json_response(201)
      |> Map.fetch!("entry")

    assert %{"entries" => []} =
             build_conn()
             |> put_bearer_token(member)
             |> get(log_path(other_organization, "/entries"))
             |> json_response(200)

    build_conn()
    |> put_bearer_token(member)
    |> get(log_path(other_organization, "/entries/#{entry["id"]}"))
    |> json_response(404)

    # Even the organization owner cannot read or void a member's entry here.
    build_conn()
    |> put_bearer_token(owner)
    |> get(log_path(organization, "/entries/#{entry["id"]}"))
    |> json_response(404)

    build_conn()
    |> put_bearer_token(owner)
    |> post(log_path(organization, "/entries/#{entry["id"]}/void"), %{})
    |> json_response(404)
  end

  test "non-members of the organization are refused", %{conn: conn} do
    {organization, _owner, _member} = organization_with_member()
    outsider = TestFixtures.user_fixture()

    conn
    |> put_bearer_token(outsider)
    |> get(log_path(organization, "/entries"))
    |> json_response(404)
  end
end
