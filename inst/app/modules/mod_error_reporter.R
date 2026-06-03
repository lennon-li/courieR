mod_error_reporter_ui <- function(id) {
  tagList()
}

mod_error_reporter_server <- function(id, error_rv) {
  moduleServer(id, function(input, output, session) {

    observeEvent(error_rv(), {
      err <- error_rv()
      if (is.null(err)) return()

      pkg_ver <- tryCatch(
        as.character(utils::packageVersion("courieR")),
        error = function(e) "unknown"
      )
      r_ver   <- paste0(R.version$major, ".", R.version$minor)
      os_info <- paste(Sys.info()[["sysname"]], Sys.info()[["release"]])

      context_line <- if (!is.null(err$context) && nzchar(err$context))
        paste0("**Context:** ", err$context, "\n\n")
      else
        ""

      body <- paste0(
        "## Error report\n\n",
        context_line,
        "**Error:**\n```\n", err$message, "\n```\n\n",
        "## Environment\n\n",
        "- courieR: `", pkg_ver, "`\n",
        "- R: `", r_ver, "`\n",
        "- OS: `", os_info, "`\n\n",
        "## Steps to reproduce\n\n",
        "<!-- Describe what you were doing when the error occurred -->\n\n",
        "1. \n2. \n3. \n"
      )

      title     <- paste0("App error: ", strtrim(err$message, 70))
      issue_url <- paste0(
        "https://github.com/lennon-li/courieR/issues/new",
        "?labels=bug",
        "&title=", utils::URLencode(title, reserved = TRUE),
        "&body=",  utils::URLencode(body,  reserved = TRUE)
      )

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
          else
            NULL
        ),
        footer = tagList(
          modalButton("Dismiss"),
          tags$a(
            href      = issue_url,
            target    = "_blank",
            rel       = "noopener noreferrer",
            class     = "btn btn-danger",
            tagList(bsicons::bs_icon("github"), " Report this bug")
          )
        ),
        easyClose = TRUE,
        size      = "m"
      ))
    }, ignoreNULL = TRUE)
  })
}
