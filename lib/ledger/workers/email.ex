defmodule Ledger.Workers.Email do
  @moduledoc """
  Delivers one transactional email. Built and enqueued by
  `Ledger.Accounts.UserNotifier`; runs on the `:mailers` queue so a flaky
  provider response is retried rather than dropping a confirmation or
  password-reset email.

  `args` carries the rendered email so the job is self-contained:
  `to`, `subject`, `text_body`, `html_body`.
  """
  use Oban.Worker, queue: :mailers, max_attempts: 5

  import Swoosh.Email

  alias Ledger.Mailer

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "to" => to,
          "subject" => subject,
          "text_body" => text_body,
          "html_body" => html_body
        }
      }) do
    new()
    |> to(to)
    |> from(Mailer.from())
    |> subject(subject)
    |> text_body(text_body)
    |> html_body(html_body)
    |> Mailer.deliver()
    |> case do
      {:ok, _meta} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
