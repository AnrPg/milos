defmodule MilosTraining.Repo.Migrations.AddFinanceDocumentMode do
  use Ecto.Migration

  def change do
    alter table(:finance_settings) do
      add :document_mode, :string, null: false, default: "invoice"
    end

    create constraint(:finance_settings, :finance_settings_document_mode_valid,
             check: "document_mode IN ('invoice', 'receipt')"
           )
  end
end
