defmodule MilosTraining.Repo.Migrations.ConstrainReviewTargetType do
  use Ecto.Migration

  @valid_target_types "'workout', 'execution', 'exercise', 'class_slot', 'gym_parameter', 'coaching_parameter', 'membership_package', 'app', 'general'"

  def up do
    execute(
      "UPDATE reviews SET target_type = 'coaching_parameter' WHERE target_type = 'private_coaching'"
    )

    create constraint(:reviews, :reviews_target_type_check,
             check: "target_type IN (#{@valid_target_types})"
           )
  end

  def down do
    drop constraint(:reviews, :reviews_target_type_check)
  end
end
