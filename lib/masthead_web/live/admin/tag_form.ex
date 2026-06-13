defmodule MastheadWeb.AdminLive.TagForm do
  use MastheadWeb, :live_view
  on_mount {MastheadWeb.AdminLive.Hooks, :load_site}

  import MastheadWeb.AdminLive.Components
  alias Masthead.Content
  alias Masthead.Content.Tag

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    tag = %Tag{}

    socket
    |> assign(tag: tag, page_title: "New tag", show_errors: false)
    |> assign_form(Content.change_tag(tag))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    tag = Content.get_tag!(socket.assigns.site.id, id)

    socket
    |> assign(tag: tag, page_title: "Edit tag", show_errors: false)
    |> assign_form(Content.change_tag(tag))
  end

  @impl true
  def handle_event("validate", %{"tag" => params}, socket) do
    changeset =
      socket.assigns.tag
      |> Content.change_tag(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"tag" => params}, socket) do
    save(socket, socket.assigns.live_action, params)
  end

  defp save(socket, :new, params) do
    case Content.create_tag(socket.assigns.site.id, params) do
      {:ok, _tag} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tag created.")
         |> push_navigate(to: ~p"/#{socket.assigns.site.slug}/tags")}

      {:error, changeset} ->
        {:noreply, socket |> assign(show_errors: true) |> assign_form(changeset)}
    end
  end

  defp save(socket, :edit, params) do
    case Content.update_tag(socket.assigns.tag, params) do
      {:ok, _tag} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tag updated.")
         |> push_navigate(to: ~p"/#{socket.assigns.site.slug}/tags")}

      {:error, changeset} ->
        {:noreply, socket |> assign(show_errors: true) |> assign_form(changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, form: to_form(changeset, as: :tag), changeset: changeset)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shell
      title={@page_title}
      site={@site}
      current_user={@current_user}
      flash={@flash}
      active={:tags}
    >
      <form phx-submit="save" phx-change="validate" class="form">
        <.error_list changeset={@changeset} show={@show_errors} />

        <label>
          Name
          <input
            type="text"
            name="tag[name]"
            value={@form[:name].value}
            required
            autofocus
            autocomplete="off"
          />
        </label>

        <label>
          Slug
          <input
            type="text"
            name="tag[slug]"
            value={@form[:slug].value}
            placeholder="auto from name"
            autocomplete="off"
          />
          <small>
            Used in theme queries:
            <code>{Ecto.Changeset.get_field(@changeset, :slug) || "your-tag"}</code>
          </small>
        </label>

        <label>
          Color
          <span class="tag-color-field">
            <input type="color" name="tag[color]" value={@form[:color].value || "#3b82f6"} />
            <small>Shown as a colored pill in the admin and exposed to your theme.</small>
          </span>
        </label>

        <div class="wizard-footer">
          <.link navigate={~p"/#{@site.slug}/tags"} class="btn">Cancel</.link>
          <button type="submit" class="btn btn-primary">
            {if @live_action == :new, do: "Create tag", else: "Save"}
          </button>
        </div>
      </form>
    </.shell>
    """
  end
end
