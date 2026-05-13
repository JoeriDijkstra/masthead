defmodule Ledger.Repo do
  use Ecto.Repo,
    otp_app: :ledger,
    adapter: Ecto.Adapters.Postgres
end
