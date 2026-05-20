defmodule LedgerWeb.AdminLive.PageForm do
  use LedgerWeb, :live_view
  on_mount {LedgerWeb.AdminLive.Hooks, :load_site}

  import LedgerWeb.AdminLive.Components
  alias Ledger.Content
  alias Ledger.Content.Page

  @impl true
  def mount(params, _session, socket) do
    {page, draft, page_title, step} =
      case socket.assigns.live_action do
        :new ->
          {nil, %{"format" => "markdown"}, "New page", 1}

        :edit ->
          page = Content.get_page!(socket.assigns.site.id, params["id"])
          {page, page_to_draft(page), "Edit: #{page.title}", 3}
      end

    {:ok,
     socket
     |> assign(
       page: page,
       step: step,
       draft: draft,
       page_title: page_title,
       slug_touched: page != nil,
       show_errors: false
     )
     |> assign_changeset(draft)}
  end

  @impl true
  def handle_event("choose_format", %{"format" => fmt}, socket)
      when fmt in ~w(markdown html blog) do
    if socket.assigns.page do
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

  def handle_event("next_meta", %{"page" => params}, socket) do
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

  def handle_event("validate", %{"page" => params} = full_params, socket) do
    target = List.last(full_params["_target"] || [])
    slug_touched = update_slug_touched(socket.assigns[:slug_touched], target, params)

    params =
      if !slug_touched and target == "title" do
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

  def handle_event("save", %{"page" => page_params} = params, socket) do
    publish? =
      case socket.assigns.page do
        nil -> Map.get(params, "action", "draft") == "publish"
        page -> page.published
      end

    full_params =
      socket.assigns.draft
      |> Map.merge(page_params)
      |> Map.put("published", to_string(publish?))

    result =
      case socket.assigns.page do
        nil -> Content.create_page(socket.assigns.site.id, full_params)
        page -> Content.update_page(page, full_params)
      end

    case result do
      {:ok, page} ->
        flash =
          case {socket.assigns.page, publish?} do
            {nil, true} -> "Page published."
            {nil, false} -> "Draft saved."
            {_, _} -> "Changes saved."
          end

        {:noreply,
         socket
         |> put_flash(:info, flash)
         |> push_navigate(to: ~p"/#{socket.assigns.site.slug}/pages/#{page.id}/edit")}

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           form: to_form(changeset, as: :page),
           changeset: changeset,
           show_errors: true
         )}
    end
  end

  def handle_event("toggle_publish", _params, socket) do
    case socket.assigns[:page] do
      nil ->
        {:noreply, socket}

      page ->
        new_published = !page.published

        case Content.update_page(page, %{"published" => to_string(new_published)}) do
          {:ok, updated} ->
            msg = if new_published, do: "Page published.", else: "Page unpublished."

            {:noreply,
             socket
             |> assign(page: updated)
             |> update(:draft, &Map.put(&1, "published", to_string(new_published)))
             |> put_flash(:info, msg)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Couldn't update publish state.")}
        end
    end
  end

  defp update_slug_touched(_prev, "slug", %{"slug" => slug}) when slug != "", do: true
  defp update_slug_touched(_prev, "slug", _params), do: false
  defp update_slug_touched(prev, _target, _params), do: prev || false

  defp page_to_draft(page) do
    %{
      "title" => page.title,
      "slug" => page.slug,
      "format" => page.format,
      "body" => page.body,
      "published" => to_string(page.published)
    }
  end

  defp build_changeset(socket, attrs) do
    base = socket.assigns[:page] || %Page{site_id: socket.assigns.site.id}
    Content.change_page(base, attrs)
  end

  defp assign_changeset(socket, attrs, opts \\ []) do
    changeset = build_changeset(socket, attrs)

    changeset =
      if Keyword.get(opts, :validate, false),
        do: Map.put(changeset, :action, :validate),
        else: changeset

    assign(socket, form: to_form(changeset, as: :page), changeset: changeset)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shell
      title={@page_title}
      site={@site}
      current_user={@current_user}
      flash={@flash}
      active={:pages}
    >
      <:actions>
        <button
          :if={@page}
          type="button"
          phx-click="toggle_publish"
          class={publish_button_class(@page.published)}
        >
          {if @page && @page.published, do: "Unpublish", else: "Publish"}
        </button>
      </:actions>

      <div class="wizard">
        <%= case @step do %>
          <% 1 -> %>
            <.format_step
              locked={@page != nil}
              format={@draft["format"]}
              editing={@page != nil}
              site_slug={@site.slug}
            />
          <% 2 -> %>
            <.meta_step
              form={@form}
              changeset={@changeset}
              format={@draft["format"]}
              editing={@page != nil}
              site_slug={@site.slug}
              show_errors={@show_errors}
            />
          <% 3 -> %>
            <.content_step
              form={@form}
              changeset={@changeset}
              format={@draft["format"]}
              editing={@page != nil}
              site_slug={@site.slug}
              show_errors={@show_errors}
            />
        <% end %>
      </div>
    </.shell>
    """
  end

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
      {if @editing, do: "Page format", else: "How do you want to write this page?"}
    </h2>

    <.format_cards selected={@format} locked={@locked} allow_blog={true} />

    <div :if={@locked} class="wizard-footer">
      <.link navigate={~p"/#{@site_slug}/pages"} class="btn">Cancel</.link>
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
        Title <input type="text" name="page[title]" value={@form[:title].value} required autofocus />
      </label>

      <label>
        Slug
        <input type="text" name="page[slug]" value={@form[:slug].value} placeholder="auto from title" />
        <small>URL: <code>/{Ecto.Changeset.get_field(@changeset, :slug) || "your-slug"}</code></small>
      </label>

      <input type="hidden" name="page[format]" value={@format} />
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

      <input type="hidden" name="page[title]" value={@form[:title].value} />
      <input type="hidden" name="page[slug]" value={@form[:slug].value} />
      <input type="hidden" name="page[format]" value={@format} />

      <%= if @format == "blog" do %>
        <.blog_description_editor form={@form} slug={Ecto.Changeset.get_field(@changeset, :slug)} />
      <% else %>
        <.body_editor form={@form} format={@format} />
      <% end %>
    </form>

    <div class="wizard-footer">
      <button type="button" phx-click="back" class="btn">&larr; Back</button>
      <div class="wizard-actions">
        <%= if @editing do %>
          <button type="submit" form="content-form" class="btn btn-primary">
            Save changes
          </button>
        <% else %>
          <button type="submit" form="content-form" name="action" value="draft" class="btn">
            Save as draft
          </button>
          <button
            type="submit"
            form="content-form"
            name="action"
            value="publish"
            class="btn btn-primary"
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
        <label for="page-body-textarea" class="editor-label">Body ({format_label(@format)})</label>
        <div
          id={"page-body-editor-" <> @format}
          class="code-editor"
          phx-hook="CodeEditor"
          phx-update="ignore"
          data-language={@format}
        >
          <textarea
            id="page-body-textarea"
            name="page[body]"
            rows="20"
            phx-debounce="200"
            class="markdown-editor"
          >{@form[:body].value}</textarea>
        </div>
      </div>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :slug, :string, default: nil

  defp blog_description_editor(assigns) do
    ~H"""
    <div class="editor editor-short">
      <div class="editor-pane">
        <label for="page-description-textarea" class="editor-label">
          Description (Markdown, optional)
        </label>
        <div
          id="page-description-editor"
          class="code-editor code-editor-short"
          phx-hook="CodeEditor"
          phx-update="ignore"
          data-language="markdown"
        >
          <textarea
            id="page-description-textarea"
            name="page[body]"
            rows="6"
            phx-debounce="200"
            class="markdown-editor"
          >{@form[:body].value}</textarea>
        </div>
        <small class="muted">
          Short intro shown above the post list. Leave empty to render just the list.
          Posts list appears at <code>/{@slug || "your-slug"}</code>.
        </small>
      </div>
    </div>
    """
  end

  defp format_label("html"), do: "HTML"
  defp format_label(_), do: "Markdown"

  defp publish_button_class(true), do: "btn btn-publish-toggle btn-published"
  defp publish_button_class(_), do: "btn btn-publish-toggle btn-draft"
end
