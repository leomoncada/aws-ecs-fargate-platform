import random
from datetime import UTC, datetime, timedelta

from app.models import Asset, Insight


def get_assets() -> list[Asset]:
    """Returns mock asset data. In production, this would query a database."""
    random.seed(42)  # Consistent data for demo
    statuses = ["active", "defaulted", "paid"]
    assets = []
    for i in range(20):
        status = random.choices(statuses, weights=[0.6, 0.2, 0.2])[0]
        due_date = datetime.now(UTC).date() + timedelta(days=random.randint(-90, 180))
        assets.append(
            Asset(
                id=f"asset-{i+1:03d}",
                nominal_value=round(random.uniform(1000, 50000), 2),
                status=status,
                due_date=due_date,
            )
        )
    return assets


def calculate_insights(assets: list[Asset]) -> list[Insight]:
    """Calculate portfolio metrics from assets."""
    total_value = sum(a.nominal_value for a in assets)
    active_assets = [a for a in assets if a.status == "active"]
    defaulted_assets = [a for a in assets if a.status == "defaulted"]
    paid_assets = [a for a in assets if a.status == "paid"]
    default_rate = len(defaulted_assets) / len(assets) if assets else 0
    outstanding_debt = sum(a.nominal_value for a in active_assets)
    collection_rate = (
        sum(a.nominal_value for a in paid_assets) / total_value if total_value else 0
    )
    return [
        Insight(
            id="insight-001",
            name="total_portfolio_value",
            value=round(total_value, 2),
        ),
        Insight(id="insight-002", name="default_rate", value=round(default_rate, 4)),
        Insight(
            id="insight-003",
            name="outstanding_debt",
            value=round(outstanding_debt, 2),
        ),
        Insight(
            id="insight-004",
            name="collection_rate",
            value=round(collection_rate, 4),
        ),
    ]
