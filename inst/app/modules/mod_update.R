mod_update_ui <- function(id) {
  ns <- NS(id)
  bslib::layout_column_wrap(
    width = 1/2,
    bslib::card(
      class = "advanced-pane advanced-update-card advanced-update-card-a",
      bslib::card_header("Update Installation A"),
      bslib::card_body(
        uiOutput(ns("badge_a")),
        div(class = "update-btn-wrap",
          actionButton(ns("update_a"), "Update A to Latest CRAN",
                       class = "btn update-btn update-btn-a")
        )
      )
    ),
    bslib::card(
      class = "advanced-pane advanced-update-card advanced-update-card-b",
      bslib::card_header("Update Installation B"),
      bslib::card_body(
        uiOutput(ns("badge_b")),
        div(class = "update-btn-wrap",
          actionButton(ns("update_b"), "Update B to Latest CRAN",
                       class = "btn update-btn update-btn-b")
        )
      )
    )
  )
}

mod_update_server <- function(id, install_a_path, install_b_path) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    pending <- reactiveVal(NULL)

    path_badge <- function(path, bucket) {
      if (is.null(path) || !nzchar(path)) {
        return(tags$p(class = "update-no-selection",
                      "Select an installation in the Sync tab first."))
      }
      tags$div(
        class = paste0("update-path-badge update-path-badge-", bucket),
        tags$span(class = "update-path-text", path)
      )
    }

    output$badge_a <- renderUI({ path_badge(install_a_path(), "a") })
    output$badge_b <- renderUI({ path_badge(install_b_path(), "b") })

    do_click <- function(path, label) {
      if (is.null(path) || !nzchar(path)) {
        showNotification("Select an installation in the Sync tab first.", type = "warning")
        return()
      }

      pkgs <- tryCatch(
        withProgress(message = paste0("Scanning installation ", label, " packages…"), {
          p <- courieR::manifest(rscript_path = path)
          p[is.na(p$priority) | !(p$priority %in% c("base", "recommended")), ]
        }),
        error = function(e) {
          showNotification(paste("Scan failed:", e$message), type = "error")
          NULL
        }
      )
      if (is.null(pkgs)) return()

      cran_mask <- !is.na(pkgs$source) & pkgs$source == "CRAN"
      cran_pkgs <- pkgs$package[cran_mask]
      non_cran  <- pkgs[!cran_mask, ]

      pending(list(path = path, label = label, cran_pkgs = cran_pkgs))

      warning_ui <- if (nrow(non_cran) > 0) {
        src_raw <- ifelse(
          is.na(non_cran$source) | non_cran$source == "unknown",
          "unknown / other", non_cran$source
        )
        src_tbl <- sort(table(src_raw), decreasing = TRUE)
        src_items <- mapply(
          function(n, s) tags$li(sprintf("%d package(s) from %s", n, s)),
          as.integer(src_tbl), names(src_tbl),
          SIMPLIFY = FALSE
        )

        preview <- paste(head(non_cran$package, 8), collapse = ", ")
        if (nrow(non_cran) > 8) {
          preview <- paste0(preview, sprintf(", … +%d more", nrow(non_cran) - 8))
        }

        tags$div(
          class = "update-modal-warning",
          tags$p(tags$strong(sprintf(
            "%d package(s) will be skipped — not from CRAN:", nrow(non_cran)
          ))),
          tags$ul(class = "update-modal-warning-list", src_items),
          tags$p(class = "update-modal-warning-pkgs", preview),
          tags$p(class = "update-modal-warning-note",
                 "GitHub, Bioconductor, and unknown-source packages must be updated manually.")
        )
      } else NULL

      showModal(modalDialog(
        title = paste0("Update Installation ", label, " to Latest CRAN"),
        if (length(cran_pkgs) > 0) {
          tags$p(sprintf(
            "%d CRAN package(s) will be upgraded to their latest versions.",
            length(cran_pkgs)
          ))
        } else {
          tags$p("No CRAN packages found to update.")
        },
        warning_ui,
        easyClose = TRUE,
        footer = tagList(
          modalButton("Cancel"),
          if (length(cran_pkgs) > 0) {
            actionButton(ns("confirm_update"), "Update", class = "btn btn-primary")
          } else {
            tags$span(class = "text-muted small", "Nothing to update.")
          }
        )
      ))
    }

    observeEvent(input$update_a, { do_click(install_a_path(), "A") })
    observeEvent(input$update_b, { do_click(install_b_path(), "B") })

    observeEvent(input$confirm_update, {
      plan <- pending()
      removeModal()
      if (is.null(plan) || length(plan$cran_pkgs) == 0) return()

      lib_res <- processx::run(
        plan$path, c("--vanilla", "-e", "cat(.libPaths()[1])"),
        error_on_status = FALSE
      )
      tgt_lib <- trimws(lib_res$stdout)
      if (lib_res$status != 0 || !nzchar(tgt_lib)) {
        showNotification("Could not determine library path.", type = "error")
        return()
      }

      specs <- plan$cran_pkgs
      ok <- tryCatch({
        withProgress(
          message = sprintf("Updating %d package(s) in installation %s…",
                            length(specs), plan$label),
          value = 0, {
            callr::r(
              func = function(specs, lib) {
                pak::pkg_install(specs, lib = lib, ask = FALSE, upgrade = TRUE)
              },
              args = list(specs = specs, lib = tgt_lib),
              show = FALSE
            )
          }
        )
        TRUE
      }, error = function(e) {
        showNotification(paste("Update failed:", e$message), type = "error", duration = NULL)
        FALSE
      })

      pending(NULL)
      if (ok) {
        showNotification(
          sprintf("Updated %d package(s) in installation %s.", length(specs), plan$label),
          type = "message"
        )
      }
    })
  })
}
