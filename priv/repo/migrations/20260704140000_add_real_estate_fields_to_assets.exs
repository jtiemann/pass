defmodule Pass.Repo.Migrations.AddRealEstateFieldsToAssets do
  use Ecto.Migration

  def change do
    alter table(:assets) do
      # Outstanding loan/mortgage against the asset.
      add :loan_balance, :decimal
      add :loan_interest_pct, :decimal
      add :loan_monthly_payment, :decimal
      # Recurring carrying cost and income (monthly, in the asset's currency).
      add :hoa_monthly, :decimal
      add :rent_monthly, :decimal
    end
  end
end
