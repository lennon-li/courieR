mod_origin_ui <- function(id) {
  ns <- NS(id)
  tagList(
    uiOutput(ns("env_summary")),
    bslib::card(
      bslib::card_header("Detected R Installations"),
      DT::dataTableOutput(ns("r_installs"))
    ),
    bslib::card(
      bslib::card_header("Installed Packages"),
      DT::dataTableOutput(ns("packages"))
    )
  )
}

mod_origin_server <- function(id, from_r_path) {
  moduleServer(id, function(input, output, session) {

    pkg_data <- reactive({
      p <- from_r_path()
      if (is.null(p) || !nzchar(p)) return(NULL)
      tryCatch(
        courieR::manifest(rscript_path = p),
        error = function(e) { showNotification(e$message, type = "error"); NULL }
      )
    })

    routes <- reactive({ courieR::find_routes() })

    output$env_summary <- renderUI({
      pkgs <- pkg_data()
      p    <- from_r_path()
      if (is.null(pkgs)) {
        return(bslib::card(bslib::card_body(
          "Select an R installation in the Sync tab."
        )))
      }
      bslib::layout_column_wrap(
        width = 1/2,
        bslib::value_box("Origin R",  basename(dirname(dirname(p)))),
        bslib::value_box("Packages",  as.character(nrow(pkgs)))
      )
    })

    output$r_installs <- DT::renderDataTable({
      dt <- routes()
      if (nrow(dt) > 0) dt <- dt[, c("version", "rscript_path", "is_current")]
      DT::datatable(dt, options = list(pageLength = 5))
    })

    output$packages <- DT::renderDataTable({
      req(pkg_data())
      DT::datatable(pkg_data(), options = list(pageLength = 15))
    })
  })
}
