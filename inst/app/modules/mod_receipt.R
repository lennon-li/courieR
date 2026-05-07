mod_receipt_ui <- function(id) {
  ns <- NS(id)
  tagList(
    uiOutput(ns("risk_banner")),
    bslib::navset_card_tab(
      bslib::nav_panel("Check Comparison", DT::dataTableOutput(ns("check_cmp"))),
      bslib::nav_panel("Test Comparison", DT::dataTableOutput(ns("test_cmp"))),
      bslib::nav_panel("Rationale", uiOutput(ns("rationale")))
    )
  )
}

mod_receipt_server <- function(id, baseline_results, post_results) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    risk_res <- reactive({
      b <- baseline_results()
      p <- post_results()
      courieR::rate_shipment(b$check, p$check)
    })

    output$risk_banner <- renderUI({
      res <- risk_res()
      theme <- switch(res$risk,
                      high = "danger",
                      medium = "warning",
                      low = "success",
                      none = "success",
                      "secondary")

      bslib::value_box(
        "Delivery Risk",
        toupper(res$risk),
        theme = theme,
        width = 12
      )
    })

    output$check_cmp <- DT::renderDataTable({
      b <- baseline_results()
      p <- post_results()
      b_check <- if (is.null(b)) NULL else b$check
      p_check <- if (is.null(p)) NULL else p$check

      if (is.null(b_check) && is.null(p_check)) {
        return(DT::datatable(
          data.frame(severity = character(), message = character(),
                     change = character())
        ))
      }

      if (is.null(b_check)) {
        p_check$change <- "new"
        return(DT::datatable(
          p_check[, .(severity, message, change)],
          options = list(pageLength = 10)
        ))
      }
      if (is.null(p_check)) {
        b_check$change <- "resolved"
        return(DT::datatable(
          b_check[, .(severity, message, change)],
          options = list(pageLength = 10)
        ))
      }

      b_key <- paste(b_check[["severity"]], b_check[["message"]], sep = "|")
      p_key <- paste(p_check[["severity"]], p_check[["message"]], sep = "|")

      new_items <- p_check[!p_key %in% b_key]
      new_items$change <- "new"

      resolved_items <- b_check[!b_key %in% p_key]
      resolved_items$change <- "resolved"

      unchanged_items <- b_check[b_key %in% p_key]
      unchanged_items$change <- "unchanged"

      DT::datatable(
        data.table::rbindlist(list(new_items, resolved_items, unchanged_items),
                              fill = TRUE)[, .(severity, message, change)],
        options = list(pageLength = 10)
      )
    })

    output$test_cmp <- DT::renderDataTable({
      b <- baseline_results()
      p <- post_results()
      b_test <- if (is.null(b)) NULL else b$test
      p_test <- if (is.null(p)) NULL else p$test

      if (is.null(b_test) && is.null(p_test)) {
        return(DT::datatable(
          data.frame(file = character(), test = character(),
                     baseline = character(), post = character())
        ))
      }

      if (is.null(b_test)) {
        out <- p_test[, .(file, test)]
        out$baseline <- "-"
        out$post <- p_test$status
        return(DT::datatable(out, options = list(pageLength = 10)))
      }
      if (is.null(p_test)) {
        out <- b_test[, .(file, test)]
        out$baseline <- b_test$status
        out$post <- "-"
        return(DT::datatable(out, options = list(pageLength = 10)))
      }

      b_key <- paste(b_test[["file"]], b_test[["test"]], sep = "|")
      p_key <- paste(p_test[["file"]], p_test[["test"]], sep = "|")

      all_keys <- unique(c(b_key, p_key))
      file_v <- sub("\\|.*", "", all_keys)
      test_v <- sub(".*?\\|", "", all_keys)

      b_idx <- match(all_keys, b_key)
      p_idx <- match(all_keys, p_key)

      bs <- ifelse(is.na(b_idx), "-", b_test[["status"]][b_idx])
      ps <- ifelse(is.na(p_idx), "-", p_test[["status"]][p_idx])

      DT::datatable(
        data.frame(file = file_v, test = test_v,
                   baseline = bs, post = ps,
                   stringsAsFactors = FALSE),
        options = list(pageLength = 10)
      )
    })

    output$rationale <- renderUI({
      res <- risk_res()
      tags$p(res$reason)
    })
  })
}
