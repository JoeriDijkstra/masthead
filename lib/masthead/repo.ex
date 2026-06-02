defmodule Masthead.Repo do
  use Ecto.Repo,
    otp_app: :masthead,
    adapter: Ecto.Adapters.Postgres
end
