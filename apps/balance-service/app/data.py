# In-memory data store
# In a production environment this would be replaced by a real database call

ACCOUNTS = {
    "ACC-001": {
        "account_id": "ACC-001",
        "owner_name": "Alejandro Camacho",
        "balance": 15420.75,
        "currency": "USD",
        "last_updated": "2026-03-15",
    },
    "ACC-002": {
        "account_id": "ACC-002",
        "owner_name": "Camila Rivero",
        "balance": 8305.20,
        "currency": "USD",
        "last_updated": "2026-03-13",
    },
    "ACC-003": {
        "account_id": "ACC-003",
        "owner_name": "Maria Gonzalez",
        "balance": 52100.00,
        "currency": "USD",
        "last_updated": "2026-03-14",
    },
}


def get_account(account_id: str) -> dict | None:
    return ACCOUNTS.get(account_id)
