defmodule Pass.Repo.Migrations.AddGrowthAssumptionsToAssets do
  use Ecto.Migration

  def change do
    alter table(:assets) do
      # Expected annual appreciation, in percent (e.g. 7.0). Nil = use the
      # historical default for the asset's category.
      add :annual_return_pct, :decimal
      # Dividend / income yield, in percent per year. Nil = none.
      add :dividend_yield_pct, :decimal
      add :dividends_reinvested, :boolean, null: false, default: true
    end
  end
end
