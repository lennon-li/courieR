mod_error_reporter_ui <- function(id) {
  tagList()
}

mod_error_reporter_server <- function(id, error_rv) {
  moduleServer(id, function(input, output, session) {

    observeEvent(error_rv(), {
      err <- error_rv()
      if (is.null(err)) return()

      issue_url <- .build_issue_url(err$message, err$context)

      showModal(modalDialog(
        title = tagList(
          bsicons::bs_icon("exclamation-triangle-fill", class = "text-danger me-2"),
          "Something went wrong"
        ),
        tagList(
          tags$p("An error occurred in courieR:"),
          tags$pre(class = "error-reporter-msg", err$message),
          if (!is.null(err$context) && nzchar(err$context))
            tags$p(class = "text-muted small", paste("Context:", err$context))
          else NULL,
          tags$p(
            class = "text-muted small mt-2 mb-0",
            "Clicking “Send Report” opens a pre-filled GitHub issue in your browser.",
            " Your R version, OS, and the error above are included. Nothing is sent automatically."
          )
        ),
        footer = tagList(
          modalButton("Dismiss"),
          actionButton(
            session$ns("send_report"), "Send Report",
            class = "btn btn-danger",
            icon  = bsicons::bs_icon("github")
          )
        ),
        easyClose = TRUE,
        size      = "m"
      ))

      # Store URL for the button observer (can't close over it directly
      # because the observer binds before the value is known at module load).
      session$userData$pending_issue_url <- issue_url
    }, ignoreNULL = TRUE)

    observeEvent(input$send_report, {
      url <- session$userData$pending_issue_url
      removeModal()
      if (!is.null(url) && nzchar(url)) {
        # window.open is more reliable than an <a href> target="_blank" — it
        # fires immediately on the button click rather than depending on the
        # browser's popup policy for server-side href navigation.
        shinyjs::runjs(sprintf("window.open(%s, '_blank');",
                               jsonlite::toJSON(url, auto_unbox = TRUE)))
      }
    })
  })
}
