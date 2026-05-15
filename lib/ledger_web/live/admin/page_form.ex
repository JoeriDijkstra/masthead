defmodule LedgerWeb.AdminLive.PageForm do
  use LedgerWeb, :live_view
  on_mount {LedgerWeb.AdminLive.Hooks, :load_site}

  import LedgerWeb.AdminLive.Components
  alias Ledger.{Content, Themes}
  alias Ledger.Content.Page

  @impl true
  def mount(params, _session, socket) do
    {page, draft, page_title, step} =
      case socket.assigns.live_action do
        :new ->
          {nil, %{"format" => "markdown"}, "New page", 1}

        :edit ->
          page = Content.get_page!(socket.assigns.site.id, params["id"])
          # Existing pages open directly on the content step (4). Reaching
          # the settings step (3) requires the Back button — it's an edit
          # affordance, not the primary path.
          {page, page_to_draft(page), "Edit: #{page.title}", 4}
      end

    metadata_fields = metadata_fields_for_site(socket.assigns.site)
    has_metadata? = metadata_fields != []

    {:ok,
     socket
     |> assign(
       page: page,
       step: step,
       draft: draft,
       page_title: page_title,
       preview_html: render_preview(draft),
       slug_touched: page != nil,
       show_errors: false,
       metadata_fields: metadata_fields,
       has_metadata?: has_metadata?
     )
     |> assign_changeset(draft)}
  end

  # Pull the metadata schema off the site's current theme. Returns a list
  # of `%{key, label, type, default, description, options}` maps, or [] if
  # the theme declares none.
  defp metadata_fields_for_site(%Ledger.Sites.Site{theme_id: id}) when is_integer(id) do
    case Themes.get_theme(id) do
      nil -> []
      theme -> extract_metadata_fields(theme.manifest)
    end
  end

  defp metadata_fields_for_site(_), do: []

  defp extract_metadata_fields(%{} = manifest) do
    list = Map.get(manifest, "metadata", Map.get(manifest, :metadata, []))

    if is_list(list) do
      Enum.map(list, fn f ->
        %{
          key: f["key"] || f[:key],
          label: f["label"] || f[:label],
          type: f["type"] || f[:type],
          default: f["default"] || f[:default],
          description: f["description"] || f[:description],
          options: f["options"] || f[:options] || []
        }
      end)
    else
      []
    end
  end

  defp extract_metadata_fields(_), do: []

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
    # Only fired from the Format step → Details.
    {:noreply, assign(socket, step: 2)}
  end

  def handle_event("back", _params, socket) do
    {:noreply, assign(socket, step: prev_step(socket))}
  end

  def handle_event("next_meta", %{"page" => params}, socket) do
    draft = Map.merge(socket.assigns.draft, params)
    changeset = build_changeset(socket, draft)

    if Ecto.Changeset.get_field(changeset, :title) not in [nil, ""] do
      # Skip the settings step entirely when the theme declares no
      # metadata — we'd render an empty step otherwise.
      next = if socket.assigns.has_metadata?, do: 3, else: 4

      {:noreply,
       socket
       |> assign(draft: draft, step: next)
       |> assign_changeset(draft)}
    else
      {:noreply,
       socket
       |> assign(draft: draft, show_errors: true)
       |> assign_changeset(draft, validate: true)}
    end
  end

  def handle_event("next_settings", %{"page" => params}, socket) do
    # Merge the metadata sub-map into the draft and advance to Content.
    draft = Map.merge(socket.assigns.draft, params)

    {:noreply,
     socket
     |> assign(draft: draft, step: 4)
     |> assign_changeset(draft)}
  end

  def handle_event("next_settings", _params, socket) do
    # Form submitted with no inputs (all blank). Still advance.
    {:noreply, assign(socket, step: 4)}
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
    preview_html = render_preview(draft)

    {:noreply,
     socket
     |> assign(draft: draft, preview_html: preview_html, slug_touched: slug_touched)
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
      "published" => to_string(page.published),
      "metadata" => page.metadata || %{}
    }
  end

  # The metadata input for the given field. The field's key lives at
  # `page[metadata][<key>]` so it gets cast into the jsonb column.
  defp metadata_value(draft, key) do
    case Map.get(draft, "metadata") do
      %{} = m -> Map.get(m, key) || Map.get(m, to_string(key)) || ""
      _ -> ""
    end
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

  defp render_preview(%{"body" => body, "format" => fmt}) when is_binary(body),
    do: Content.render_body(body, fmt || "markdown")

  defp render_preview(_), do: ""

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
              has_metadata={@has_metadata?}
            />
          <% 2 -> %>
            <.meta_step
              form={@form}
              changeset={@changeset}
              format={@draft["format"]}
              editing={@page != nil}
              site_slug={@site.slug}
              show_errors={@show_errors}
              has_metadata={@has_metadata?}
            />
          <% 3 -> %>
            <.settings_step
              fields={@metadata_fields}
              draft={@draft}
              has_metadata={@has_metadata?}
            />
          <% 4 -> %>
            <.content_step
              form={@form}
              changeset={@changeset}
              format={@draft["format"]}
              preview_html={@preview_html}
              editing={@page != nil}
              site_slug={@site.slug}
              show_errors={@show_errors}
              has_metadata={@has_metadata?}
            />
        <% end %>
      </div>
    </.shell>
    """
  end

  attr :step, :integer, default: 1
  attr :has_metadata, :boolean, default: false

  defp stepper(assigns) do
    assigns = assign(assigns, :entries, Enum.with_index(visible_steps(assigns.has_metadata), 1))

    ~H"""
    <ol class="stepper">
      <li
        :for={{{step_num, label}, display_idx} <- @entries}
        class={"step " <> step_class(step_num, @step)}
      >
        <span class="step-num">{display_idx}</span>
        <span class="step-label">{label}</span>
      </li>
    </ol>
    """
  end

  defp step_class(i, current) when i < current, do: "step-done"
  defp step_class(i, current) when i == current, do: "step-current"
  defp step_class(_, _), do: "step-future"

  # Returns [{internal_step, label}, ...]. The settings step is omitted
  # when the active theme declares no metadata fields.
  defp visible_steps(true),
    do: [{1, "Format"}, {2, "Details"}, {3, "Page settings"}, {4, "Content"}]

  defp visible_steps(false),
    do: [{1, "Format"}, {2, "Details"}, {4, "Content"}]

  # Previous step for the Back button. Skips step 3 when there's no
  # metadata so the user doesn't land on a blank screen.
  defp prev_step(%{assigns: %{step: 4, has_metadata?: false}}), do: 2
  defp prev_step(%{assigns: %{step: step}}) when step > 1, do: step - 1
  defp prev_step(_), do: 1

  attr :locked, :boolean, default: false
  attr :format, :string, default: nil
  attr :editing, :boolean, default: false
  attr :site_slug, :string, required: true
  attr :has_metadata, :boolean, default: false

  defp format_step(assigns) do
    ~H"""
    <.stepper step={1} has_metadata={@has_metadata} />

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
  attr :has_metadata, :boolean, default: false

  defp meta_step(assigns) do
    ~H"""
    <.stepper step={2} has_metadata={@has_metadata} />

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

  attr :fields, :list, required: true
  attr :draft, :map, required: true
  attr :has_metadata, :boolean, default: true

  defp settings_step(assigns) do
    ~H"""
    <.stepper step={3} has_metadata={@has_metadata} />

    <h2 class="wizard-heading">Page settings</h2>
    <p class="wizard-intro muted">
      Theme-specific overrides for this page. Blank fields fall back to
      the theme default.
    </p>

    <form id="settings-form" phx-submit="next_settings" class="form">
      <div class="settings-fields">
        <.metadata_field :for={f <- @fields} field={f} value={metadata_value(@draft, f.key)} />
      </div>
    </form>

    <div class="wizard-footer">
      <button type="button" phx-click="back" class="btn">&larr; Back</button>
      <button type="submit" form="settings-form" class="btn btn-primary">Continue &rarr;</button>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :changeset, :map, required: true
  attr :format, :string, required: true
  attr :preview_html, :string, required: true
  attr :editing, :boolean, default: false
  attr :site_slug, :string, required: true
  attr :show_errors, :boolean, default: false
  attr :has_metadata, :boolean, default: false

  defp content_step(assigns) do
    ~H"""
    <.stepper step={4} has_metadata={@has_metadata} />

    <form id="content-form" phx-submit="save" phx-change="validate" class="form post-form">
      <.error_list changeset={@changeset} show={@show_errors} />

      <input type="hidden" name="page[title]" value={@form[:title].value} />
      <input type="hidden" name="page[slug]" value={@form[:slug].value} />
      <input type="hidden" name="page[format]" value={@format} />

      <%= if @format == "blog" do %>
        <.blog_description_editor
          form={@form}
          preview_html={@preview_html}
          slug={Ecto.Changeset.get_field(@changeset, :slug)}
        />
      <% else %>
        <.body_editor form={@form} format={@format} preview_html={@preview_html} />
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
  attr :preview_html, :string, required: true

  defp body_editor(assigns) do
    ~H"""
    <div class="editor">
      <div class="editor-pane">
        <label for="page-body-textarea" class="editor-label">Body ({format_label(@format)})</label>
        <textarea
          id="page-body-textarea"
          name="page[body]"
          rows="20"
          phx-debounce="200"
          class="markdown-editor"
        >{@form[:body].value}</textarea>
      </div>
      <div class="editor-pane">
        <div class="editor-label">Preview</div>
        <div class="preview prose">{Phoenix.HTML.raw(@preview_html)}</div>
      </div>
    </div>
    """
  end

  attr :form, :map, required: true
  attr :preview_html, :string, required: true
  attr :slug, :string, default: nil

  defp blog_description_editor(assigns) do
    ~H"""
    <div class="editor editor-short">
      <div class="editor-pane">
        <label for="page-description-textarea" class="editor-label">
          Description (Markdown, optional)
        </label>
        <textarea
          id="page-description-textarea"
          name="page[body]"
          rows="6"
          phx-debounce="200"
          class="markdown-editor"
        >{@form[:body].value}</textarea>
        <small class="muted">
          Short intro shown above the post list. Leave empty to render just the list.
        </small>
      </div>
      <div class="editor-pane">
        <div class="editor-label">Preview</div>
        <div class="preview prose blog-preview">
          <div :if={@preview_html != ""}>{Phoenix.HTML.raw(@preview_html)}</div>
          <p :if={@preview_html == ""} class="muted">
            (no description — the post list will appear directly below the title)
          </p>
          <div class="blog-preview-divider">
            <span>Posts list appears here at <code>/{@slug || "your-slug"}</code></span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_label("html"), do: "HTML"
  defp format_label(_), do: "Markdown"

  attr :field, :map, required: true
  attr :value, :any, required: true

  defp metadata_field(%{field: %{type: "boolean"}} = assigns) do
    assigns = assign(assigns, :checked?, truthy?(assigns.value, assigns.field.default))

    ~H"""
    <label class="checkbox-label">
      <input type="hidden" name={"page[metadata][" <> @field.key <> "]"} value="false" />
      <input
        type="checkbox"
        name={"page[metadata][" <> @field.key <> "]"}
        value="true"
        checked={@checked?}
      />
      <span>{@field.label}</span>
      <small :if={@field.description}>{@field.description}</small>
    </label>
    """
  end

  defp metadata_field(%{field: %{type: "select"}} = assigns) do
    ~H"""
    <label>
      {@field.label}
      <select name={"page[metadata][" <> @field.key <> "]"}>
        <option
          :for={opt <- @field.options}
          value={opt}
          selected={to_string(opt) == to_string((@value == "" && @field.default) || @value)}
        >
          {opt}
        </option>
      </select>
      <small :if={@field.description}>{@field.description}</small>
    </label>
    """
  end

  defp metadata_field(%{field: %{type: "text"}} = assigns) do
    ~H"""
    <label>
      {@field.label}
      <textarea
        name={"page[metadata][" <> @field.key <> "]"}
        rows="3"
        placeholder={to_string(@field.default || "")}
      >{@value}</textarea>
      <small :if={@field.description}>{@field.description}</small>
    </label>
    """
  end

  defp metadata_field(assigns) do
    ~H"""
    <label>
      {@field.label}
      <input
        type={metadata_input_type(@field.type)}
        name={"page[metadata][" <> @field.key <> "]"}
        value={@value}
        placeholder={to_string(@field.default || "")}
      />
      <small :if={@field.description}>{@field.description}</small>
    </label>
    """
  end

  defp metadata_input_type("color"), do: "color"
  defp metadata_input_type("number"), do: "number"
  defp metadata_input_type("url"), do: "url"
  defp metadata_input_type(_), do: "text"

  defp truthy?(value, default) do
    case value do
      v when v in [true, "true", "on", "1", 1] -> true
      v when v in [false, "false", "0", 0, nil, ""] -> false
      _ -> truthy?(default, false)
    end
  end

  defp publish_button_class(true), do: "btn btn-publish-toggle btn-published"
  defp publish_button_class(_), do: "btn btn-publish-toggle btn-draft"
end
