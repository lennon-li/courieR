server <- function(input, output, session) {
  from_r_path   <- reactiveVal(NULL)
  to_r_path     <- reactiveVal(NULL)
  selected_pkgs <- reactiveVal(NULL)
  migration_log <- reactiveVal(NULL)

  output$details_panel <- renderUI({
    src <- from_r_path()
    tgt <- to_r_path()
    bslib::layout_column_wrap(
      width = 1/2,
      bslib::card(
        bslib::card_header("Origin R"),
        bslib::card_body(if (is.null(src)) "Not selected" else src)
      ),
      bslib::card(
        bslib::card_header("Destination R"),
        bslib::card_body(if (is.null(tgt)) "Not selected" else tgt)
      )
    )
  })

  mod_migrate_server("migrate", from_r_path, to_r_path, selected_pkgs, migration_log)
  mod_origin_server("env", from_r_path)
  mod_receipt_server("results", migration_log)
  mod_manifest_server("report", from_r_path, to_r_path, migration_log)
}
