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

# Build a pre-filled GitHub new-issue URL with diagnostics collected from the
# current R session. Exported so CLI users can call report_issue() directly.
.build_issue_url <- function(message, context = NULL) {
  pkg_ver  <- tryCatch(as.character(utils::packageVersion("courieR")), error = function(e) "unknown")
  r_ver    <- paste0(R.version$major, ".", R.version$minor)
  os_info  <- paste(Sys.info()[["sysname"]], Sys.info()[["release"]])
  platform <- R.version$platform
  n_routes <- tryCatch({
    r <- courieR::find_routes()
    sprintf("%d installation(s) detected", nrow(r))
  }, error = function(e) "detection not run")

  context_line <- if (!is.null(context) && nzchar(context))
    paste0("**Context:** ", context, "\n\n")
  else ""

  body <- paste0(
    "## Error report\n\n",
    context_line,
    "**Error:**\n```\n", message, "\n```\n\n",
    "## Environment\n\n",
    "| Field | Value |\n",
    "|-------|-------|\n",
    "| courieR | `", pkg_ver, "` |\n",
    "| R | `", r_ver, "` |\n",
    "| Platform | `", platform, "` |\n",
    "| OS | `", os_info, "` |\n",
    "| Routes | ", n_routes, " |\n\n",
    "## Steps to reproduce\n\n",
    "<!-- Describe what you were doing when the error occurred -->\n\n",
    "1. \n2. \n3. \n"
  )

  title <- paste0("App error: ", strtrim(message, 70))
  paste0(
    "https://github.com/lennon-li/courieR/issues/new",
    "?labels=bug",
    "&title=", utils::URLencode(title, reserved = TRUE),
    "&body=",  utils::URLencode(body,  reserved = TRUE)
  )
}
