defmodule Ledger.Actions.Action do
  @moduledoc """
  A one-off, site-scoped task ("action") surfaced to the site owner in the
  admin checklist. Each action is unique per `(site_id, key)`; the `key`
  identifies its type (see `Ledger.Actions.Definitions`).

  Fields:

    * `key`      — stable identifier of the action type, unique per site
    * `status`   — `"pending"`, `"completed"`, or `"dismissed"`
    * `message`  — the message shown to the user
    * `priority` — higher numbers surface first
    * `path`     — optional admin path the action's button links to
    * `reminded_at` — set when a one-off reminder email was sent (never re-sent)
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending completed dismissed)

  schema "actions" do
    field :key, :string
    field :status, :string, default: "pending"
    field :message, :string
    field :priority, :integer, default: 0
    field :path, :string
    field :reminded_at, :utc_datetime

    belongs_to :site, Ledger.Sites.Site

    timestamps(type: :utc_datetime)
  end

  def changeset(action, attrs) do
    action
    |> cast(attrs, [:key, :status, :message, :priority, :path, :site_id])
    |> validate_required([:key, :status, :site_id])
    |> validate_inclusion(:status, @statuses)
    |> assoc_constraint(:site)
    |> unique_constraint([:site_id, :key], name: :actions_site_id_key_index)
  end
end
