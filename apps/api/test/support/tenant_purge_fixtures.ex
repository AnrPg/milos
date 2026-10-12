defmodule MilosTraining.TenantPurgeFixtures do
  @moduledoc """
  Seeds a tenant with data across bounded contexts - including the RESTRICT
  chains (scheduled class -> workout) that blocked the old permanent delete -
  plus stored objects, for ADR-117 purge tests.
  """

  import MilosTraining.TestFixtures

  alias MilosTraining.Application.{TenantDataContexts, TenantObjectStorage}
  alias MilosTraining.{Finance, Organizations, Repo}
  alias MilosTraining.Gamification.{GamificationSetting, UserAchievement}
  alias MilosTraining.Notifications.Notification
  alias MilosTraining.Pantheon.PRRecord
  alias MilosTraining.TestSupport.MemoryObjectStore

  def seed_tenant(name, opts \\ []) do
    owner = admin_fixture()
    member = user_fixture()
    shared = Keyword.get(opts, :shared_user)

    {:ok, organization} = Organizations.create_organization(%{name: name})

    for {user, role} <- [{owner, :owner}, {member, :member}] ++ shared_membership(shared) do
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)

    {:ok, finance_membership} =
      Finance.upsert_membership(context, member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {:ok, invoice} =
      Finance.create_invoice(context, finance_membership.id, %{
        amount_cents: 4_500,
        description: "#{name} monthly",
        due_date: Date.add(Date.utc_today(), 7)
      })

    {:ok, _issued} = Finance.issue_invoice(context, invoice.id, %{})

    workout = workout_fixture(owner, %{tenant_context: context})
    class_type = class_type_fixture(%{tenant_context: context})

    _slot =
      slot_fixture(workout, %{tenant_context: context, class_type_id: class_type.id})

    Repo.insert!(
      GamificationSetting.changeset(%GamificationSetting{}, %{
        organization_id: organization.id,
        weekly_workout_target: 3,
        leaderboard_enabled: true,
        theme_slug: "ember"
      })
    )

    Repo.insert!(%Notification{
      organization_id: organization.id,
      user_id: member.id,
      type: :booking_approved,
      payload: %{"seed" => name}
    })

    Repo.insert!(
      PRRecord.changeset(%PRRecord{organization_id: organization.id}, %{
        user_id: member.id,
        name: "Back Squat",
        current_score: 100,
        unit: "kg",
        beaten_on: Date.utc_today()
      })
    )

    Repo.insert!(%UserAchievement{
      organization_id: organization.id,
      user_id: member.id,
      badge_key: "first_workout",
      earned_at: DateTime.utc_now()
    })

    {:ok, invoice_key} =
      TenantObjectStorage.put_tenant_object(
        organization.id,
        "invoices/#{invoice.id}/receipt.pdf",
        "%PDF-#{name}",
        "application/pdf"
      )

    {:ok, logo_key} =
      TenantObjectStorage.put_tenant_object(
        organization.id,
        "branding/logo.png",
        "png-#{name}",
        "image/png"
      )

    avatar_key = "users/#{member.id}/avatars/#{Ecto.UUID.generate()}.png"
    :ok = MemoryObjectStore.put_object(:avatars, avatar_key, "avatar", "image/png")

    %{
      organization: organization,
      context: context,
      owner: owner,
      member: member,
      shared: shared,
      invoice_key: invoice_key,
      logo_key: logo_key,
      avatar_key: avatar_key
    }
  end

  @doc "Row counts of every context-declared tenant table for one organization."
  def tenant_row_counts(organization_id) do
    policies =
      TenantDataContexts.policies() ++ [Organizations.tenant_data_policy()]

    for policy <- policies,
        spec <- policy.tables,
        into: %{} do
      {spec.table, count_rows(spec, organization_id)}
    end
  end

  defp count_rows(%{parent: {parent, fk}, table: table}, organization_id) do
    %{rows: [[count]]} =
      Repo.query!(
        ~s|SELECT count(*) FROM "#{table}" WHERE "#{fk}" IN (SELECT id FROM "#{parent}" WHERE organization_id = $1)|,
        [Ecto.UUID.dump!(organization_id)]
      )

    count
  end

  defp count_rows(%{table: table}, organization_id) do
    %{rows: [[count]]} =
      Repo.query!(~s|SELECT count(*) FROM "#{table}" WHERE organization_id = $1|, [
        Ecto.UUID.dump!(organization_id)
      ])

    count
  end

  defp shared_membership(nil), do: []
  defp shared_membership(user), do: [{user, :member}]
end
