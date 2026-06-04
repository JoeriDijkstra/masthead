defmodule MastheadWeb.AdminLive.PostForm do
  use MastheadWeb, :live_view
  on_mount {MastheadWeb.AdminLive.Hooks, :load_site}

  import MastheadWeb.AdminLive.Components
  alias Masthead.Content
  alias Masthead.Content.Post

  @impl true
  def mount(params, _session, socket) do
    {post, draft, page_title, step} =
      case socket.assigns.live_action do
        :new ->
          {nil, %{"format" => "markdown"}, "New post", 1}

        :edit ->
          post = Content.get_post!(socket.assigns.site.id, params["id"])
          # Open existing posts directly on the content step — most edits
          # are body tweaks; format and details are reachable via Back.
          {post, post_to_draft(post), "Edit: #{post.title}", 3}
      end

    {:ok,
     socket
     |> assign(
       post: post,
       step: step,
       draft: draft,
       page_title: page_title,
       slug_touched: post != nil,
       show_errors: false
     )
     |> assign_changeset(draft)}
  end

  # ---- Step navigation ----

  @impl true
  def handle_event("choose_format", %{"format" => fmt}, socket) when fmt in ~w(markdown html) do
    if socket.assigns.post do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> update(:draft, &Map.put(&1, "format", fmt))
       |> assign(step: 2)}
    end
  end

  def handle_event("advance", _params, socket) do
    {:noreply, assign(socket, step: min(socket.assigns.step + 1, 3))}
  end

  def handle_event("back", _params, socket) do
    {:noreply, assign(socket, step: max(socket.assigns.step - 1, 1))}
  end

  def handle_event("next_meta", %{"post" => params}, socket) do
    draft = Map.merge(socket.assigns.draft, params)
    changeset = build_changeset(socket, draft)

    if Ecto.Changeset.get_field(changeset, :title) not in [nil, ""] do
      {:noreply,
       socket
       |> assign(draft: draft, step: 3)
       |> assign_changeset(draft)}
    else
      {:noreply,
       socket
       |> assign(draft: draft, show_errors: true)
       |> assign_changeset(draft, validate: true)}
    end
  end

  # ---- Validation / save ----

  def handle_event("validate", %{"post" => params} = full_params, socket) do
    target = List.last(full_params["_target"] || [])
    slug_touched = update_slug_touched(socket.assigns[:slug_touched], target, params)

    params =
      if !slug_touched and target == "title" do
        # Force ensure_slug to re-derive from the (just-changed) title by
        # blanking the slug. Otherwise the previous derived value sticks.
        Map.put(params, "slug", "")
      else
        params
      end

    draft = Map.merge(socket.assigns.draft, params)

    {:noreply,
     socket
     |> assign(draft: draft, slug_touched: slug_touched)
     |> assign_changeset(draft, validate: true)}
  end

  def handle_event("save", %{"post" => post_params} = params, socket) do
    # New posts use the explicit "draft" / "publish" action from one of two
    # buttons. Existing posts have a single "Save" button — preserve the
    # post's current published state (the page-head toggle changes that
    # independently).
    publish? =
      case socket.assigns.post do
        nil -> Map.get(params, "action", "draft") == "publish"
        post -> post.published
      end

    full_params =
      socket.assigns.draft
      |> Map.merge(post_params)
      |> Map.put("published", to_string(publish?))

    result =
      case socket.assigns.post do
        nil -> Content.create_post(socket.assigns.site.id, full_params)
        post -> Content.update_post(post, full_params)
      end

    case result do
      {:ok, post} ->
        flash =
          case {socket.assigns.post, publish?} do
            {nil, true} -> "Post published."
            {nil, false} -> "Draft saved."
            {_, _} -> "Changes saved."
          end

        if socket.assigns.post do
          # Existing post: re-render in place. A push_navigate here would
          # remount the page (and the CodeEditor hook), rebuilding CodeMirror
          # from scratch and wiping its undo history — so Cmd+Z stops working
          # after every Cmd+S save. The editor is phx-update="ignore", so an
          # in-place update leaves it (and its undo stack) untouched.
          draft = post_to_draft(post)

          {:noreply,
           socket
           |> put_flash(:info, flash)
           |> assign(
             post: post,
             draft: draft,
             page_title: "Edit: #{post.title}",
             show_errors: false
           )
           |> assign_changeset(draft)}
        else
          # New post: the URL must change from /new to /:id/edit, so navigate.
          {:noreply,
           socket
           |> put_flash(:info, flash)
           |> push_navigate(to: ~p"/#{socket.assigns.site.slug}/posts/#{post.id}/edit")}
        end

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           form: to_form(changeset, as: :post),
           changeset: changeset,
           show_errors: true
         )}
    end
  end

  def handle_event("toggle_publish", _params, socket) do
    case socket.assigns[:post] do
      nil ->
        {:noreply, socket}

      post ->
        new_published = !post.published

        case Content.update_post(post, %{"published" => to_string(new_published)}) do
          {:ok, updated} ->
            msg = if new_published, do: "Post published.", else: "Post unpublished."

            {:noreply,
             socket
             |> assign(post: updated)
             |> update(:draft, &Map.put(&1, "published", to_string(new_published)))
             |> put_flash(:info, msg)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Couldn't update publish state.")}
        end
    end
  end

  # ---- Helpers ----

  defp update_slug_touched(_prev, "slug", %{"slug" => slug}) when slug != "", do: true
  defp update_slug_touched(_prev, "slug", _params), do: false
  defp update_slug_touched(prev, _target, _params), do: prev || false

  defp post_to_draft(post) do
    %{
      "title" => post.title,
      "slug" => post.slug,
      "excerpt" => post.excerpt,
      "format" => post.format,
      "body" => post.body,
      "published" => to_string(post.published)
    }
  end

  defp build_changeset(socket, attrs) do
    base = socket.assigns[:post] || %Post{site_id: socket.assigns.site.id}
    Content.change_post(base, attrs)
  end

  defp assign_changeset(socket, attrs, opts \\ []) do
    changeset = build_changeset(socket, attrs)

    changeset =
      if Keyword.get(opts, :validate, false),
        do: Map.put(changeset, :action, :validate),
        else: changeset

    assign(socket, form: to_form(changeset, as: :post), changeset: changeset)
  end

  # ---- Render ----

  @impl true
  def render(assigns) do
    ~H"""
    <.shell
      title={@page_title}
      site={@site}
      current_user={@current_user}
      flash={@flash}
      active={:posts}
    >
      <:actions>
        <button
          :if={@post}
          type="button"
          phx-click="toggle_publish"
          class={publish_button_class(@post.published)}
        >
          {if @post && @post.published, do: "Unpublish", else: "Publish"}
        </button>
      </:actions>

      <div class="wizard">
        <%= case @step do %>
          <% 1 -> %>
            <.format_step
              locked={@post != nil}
              format={@draft["format"]}
              editing={@post != nil}
              site_slug={@site.slug}
            />
          <% 2 -> %>
            <.meta_step
              form={@form}
              changeset={@changeset}
              format={@draft["format"]}
              editing={@post != nil}
              site_slug={@site.slug}
              show_errors={@show_errors}
            />
          <% 3 -> %>
            <.content_step
              form={@form}
              changeset={@changeset}
              format={@draft["format"]}
              editing={@post != nil}
              site_slug={@site.slug}
              show_errors={@show_errors}
            />
        <% end %>
      </div>
    </.shell>
    """
  end

  defp publish_button_class(true), do: "btn btn-publish-toggle btn-published"
  defp publish_button_class(_), do: "btn btn-publish-toggle btn-draft"

  attr :step, :integer, default: 1

  defp stepper(assigns) do
    ~H"""
    <ol class="stepper">
      <li :for={i <- 1..3} class={"step " <> step_class(i, @step)}>
        <span class="step-num">{i}</span>
        <span class="step-label">{step_label(i)}</span>
      </li>
    </ol>
    """
  end

  defp step_class(i, current) when i < current, do: "step-done"
  defp step_class(i, current) when i == current, do: "step-current"
  defp step_class(_, _), do: "step-future"

  defp step_label(1), do: "Format"
  defp step_label(2), do: "Details"
  defp step_label(3), do: "Content"

  attr :locked, :boolean, default: false
  attr :format, :string, default: nil
  attr :editing, :boolean, default: false
  attr :site_slug, :string, required: true

  defp format_step(assigns) do
    ~H"""
    <.stepper step={1} />

    <h2 class="wizard-heading">
      {if @editing, do: "Post format", else: "How do you want to write this post?"}
    </h2>

    <.format_cards selected={@format} locked={@locked} />

    <div :if={@locked} class="wizard-footer">
      <.link navigate={~p"/#{@site_slug}/posts"} class="btn">Cancel</.link>
      <span class="muted">Format is set at creation and cannot be changed.</span>
      <button type="button" phx-click="advance" class="btn btn-primary">Continue &rarr;</button>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :changeset, :map, required: true
  attr :format, :string, required: true
  attr :editing, :boolean, default: false
  attr :site_slug, :string, required: true
  attr :show_errors, :boolean, default: false

  defp meta_step(assigns) do
    ~H"""
    <.stepper step={2} />

    <form id="meta-form" phx-submit="next_meta" phx-change="validate" class="form">
      <.error_list changeset={@changeset} show={@show_errors} />

      <label>
        Title <input type="text" name="post[title]" value={@form[:title].value} required autofocus />
      </label>

      <label>
        Slug
        <input type="text" name="post[slug]" value={@form[:slug].value} placeholder="auto from title" />
        <small>
          URL: <code>/posts/{Ecto.Changeset.get_field(@changeset, :slug) || "your-slug"}</code>
        </small>
      </label>

      <label>
        Excerpt <textarea
          name="post[excerpt]"
          rows="3"
          placeholder="One or two sentences shown on the homepage and in the &lt;meta&gt; description."
        >{@form[:excerpt].value}</textarea>
      </label>

      <input type="hidden" name="post[format]" value={@format} />
    </form>

    <div class="wizard-footer">
      <button type="button" phx-click="back" class="btn">&larr; Back</button>
      <span class="muted">Writing in <strong>{format_label(@format)}</strong></span>
      <button type="submit" form="meta-form" class="btn btn-primary">Continue &rarr;</button>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :changeset, :map, required: true
  attr :format, :string, required: true
  attr :editing, :boolean, default: false
  attr :site_slug, :string, required: true
  attr :show_errors, :boolean, default: false

  defp content_step(assigns) do
    ~H"""
    <.stepper step={3} />

    <form id="content-form" phx-submit="save" phx-change="validate" class="form post-form">
      <.error_list changeset={@changeset} show={@show_errors} />

      <input type="hidden" name="post[title]" value={@form[:title].value} />
      <input type="hidden" name="post[slug]" value={@form[:slug].value} />
      <input type="hidden" name="post[excerpt]" value={@form[:excerpt].value} />
      <input type="hidden" name="post[format]" value={@format} />

      <.body_editor form={@form} format={@format} />
    </form>

    <div class="wizard-footer">
      <button type="button" phx-click="back" class="btn">&larr; Back</button>
      <div class="wizard-actions">
        <%= if @editing do %>
          <button type="submit" form="content-form" class="btn btn-primary" data-shortcut="save">
            Save changes
          </button>
        <% else %>
          <button
            type="submit"
            form="content-form"
            name="action"
            value="draft"
            class="btn"
            data-shortcut="save"
          >
            Save as draft
          </button>
          <button
            type="submit"
            form="content-form"
            name="action"
            value="publish"
            class="btn btn-primary"
            data-shortcut="publish"
          >
            Save &amp; publish
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :format, :string, required: true

  defp body_editor(assigns) do
    ~H"""
    <div class="editor">
      <div class="editor-pane">
        <label for="post-body-textarea" class="editor-label">Body ({format_label(@format)})</label>
        <div
          id={"post-body-editor-" <> @format}
          class="code-editor"
          phx-hook="CodeEditor"
          phx-update="ignore"
          data-language={@format}
        >
          <textarea
            id="post-body-textarea"
            name="post[body]"
            rows="20"
            phx-debounce="200"
            class="markdown-editor"
          >{@form[:body].value}</textarea>
        </div>
      </div>
    </div>
    """
  end

  defp format_label("html"), do: "HTML"
  defp format_label(_), do: "Markdown"
end
