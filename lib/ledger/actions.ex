defmodule Ledger.Actions do
  @moduledoc """
  One-off, site-scoped tasks ("actions") surfaced in the admin checklist.

  Actions are created from a registry of known types
  (`Ledger.Actions.Definitions`) and are idempotent on both ends:

    * `create_action/2` is a no-op if the `(site, key)` action already
      exists (the action is a "one-off").
    * `complete_action/2` is a no-op if the action is missing or already
      completed.
  """
  import Ecto.Query

  alias Ledger.Repo
  alias Ledger.Sites.Site
  alias Ledger.Actions.{Action, Definitions}

  @doc """
  Creates the action of type `key` for `site`, drawing its message/priority/
  path from the registry. Idempotent: a duplicate `(site, key)` is ignored,
  so it is safe to call on every site creation. Returns `{:ok, action}`,
  `{:ok, :exists}` when it already existed, or `{:error, :unknown_key}`.
  """
  def create_action(%Site{} = site, key) when is_binary(key) do
    case Definitions.build_attrs(key, site) do
      nil ->
        {:error, :unknown_key}

      attrs ->
        %Action{}
        |> Action.changeset(attrs)
        |> Repo.insert(on_conflict: :nothing, conflict_target: [:site_id, :key])
        |> case do
          {:ok, %Action{id: nil}} -> {:ok, :exists}
          {:ok, action} -> {:ok, action}
          other -> other
        end
    end
  end

  @doc """
  Marks the `(site, key)` action completed. Accepts a `%Site{}` or a bare
  site id. Idempotent: returns `:ok` whether the action was pending, already
  completed, or absent.
  """
  def complete_action(%Site{id: site_id}, key), do: complete_action(site_id, key)

  def complete_action(site_id, key) when is_integer(site_id) and is_binary(key) do
    {_count, _} =
      from(a in Action,
        where: a.site_id == ^site_id and a.key == ^key and a.status != "completed"
      )
      |> Repo.update_all(set: [status: "completed", updated_at: now()])

    :ok
  end

  @doc """
  Dismisses the `(site, key)` action — the owner has chosen to skip it.
  Accepts a `%Site{}` or a bare site id. Only affects a `pending` action
  (a completed one stays completed). Idempotent: returns `:ok` regardless.
  """
  def dismiss_action(%Site{id: site_id}, key), do: dismiss_action(site_id, key)

  def dismiss_action(site_id, key) when is_integer(site_id) and is_binary(key) do
    {_count, _} =
      from(a in Action,
        where: a.site_id == ^site_id and a.key == ^key and a.status == "pending"
      )
      |> Repo.update_all(set: [status: "dismissed", updated_at: now()])

    :ok
  end

  @doc "Pending actions for `site`, highest priority first."
  def list_pending(%Site{id: site_id}), do: Repo.all(pending_query(site_id))

  @doc "Count of pending actions for `site` (used for the checklist badge)."
  def count_pending(%Site{id: site_id}) do
    Repo.aggregate(
      from(a in Action, where: a.site_id == ^site_id and a.status == "pending"),
      :count
    )
  end

  @doc "The single highest-priority pending action for `site`, or `nil`."
  def top_action(%Site{id: site_id}) do
    site_id |> pending_query() |> limit(1) |> Repo.one()
  end

  @doc "Render-time title for an action."
  def title(%Action{key: key}), do: Definitions.title(key)

  @doc "Render-time button label for an action, or `nil`."
  def cta(%Action{key: key}), do: Definitions.cta(key)

  defp pending_query(site_id) do
    from a in Action,
      where: a.site_id == ^site_id and a.status == "pending",
      order_by: [desc: a.priority, asc: a.inserted_at]
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
