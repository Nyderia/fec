#' ETL operations for FEC data
#' 
#' @inheritParams etl::etl_extract
#' @param years a vector of integers representing the years
#' @details If a \code{year} and/or \code{month} is specified, then
#' only flight data from matching months is used.
#' @export
#' @import etl
#' @examples 
#' 
#' \dontrun{
#' fec <- etl("fec", dir = "~/dumps/fec")
#' fec %>%
#'   etl_extract() %>%
#'   etl_transform() %>%
#'   etl_load()
#' }
etl_extract.etl_fec <- function(obj, years = 2012, ...) {
  
  src_root <- "ftp://ftp.fec.gov/FEC/2012/"
  src_files <- c("cn12.zip", "cm12.zip", "pas212.zip", "indiv12.zip")
  src <- paste0(src_root, src_files)
  
  lcl <- paste0(attr(obj, "raw_dir"), "/", basename(src))
  missing <- !file.exists(lcl)
  
  mapply(download.file, src[missing], lcl[missing])
  invisible(obj)
}

#' @rdname etl_extract.etl_fec
#' @importFrom readr read_delim write_csv
#' @export
etl_transform.etl_fec <- function(obj, years = 2012, ...) {
  
  src <- paste0(attr(obj, "raw_dir"), "/", 
                      c("cn12.zip", "cm12.zip", "pas212.zip", "indiv12.zip"))
  src_headers <- paste0("http://www.fec.gov/finance/disclosure/metadata/", 
                         c("cn_header_file.csv", "cm_header_file.csv", 
                           "pas2_header_file.csv", "indiv_header_file.csv"))
  headers <- lapply(src_headers, readr::read_csv) %>%
    lapply(names)
  files <- mapply(readr::read_delim, file = src, col_names = headers, MoreArgs = list(delim = "|"))
  names(files) <- c("candidates", "committees", "contributions", "individuals")
  
  files <- lapply(files, function(x) { names(x) <- tolower(names(x)); x; })
  
  lcl <- paste0(attr(obj, "load_dir"), "/", names(files), "_2012.csv")
  mapply(readr::write_csv, files, path = lcl, na = "")
  
  invisible(obj)
}

#' @rdname etl_extract.etl_fec
#' @importFrom DBI dbWriteTable dbListTables
#' @export
#' 
#' \dontrun{
#' if (require(RMySQL)) {
#'   # must have pre-existing database "fec"
#'   # if not, try
#'   system("mysql -e 'CREATE DATABASE IF NOT EXISTS fec;'")
#'   db <- src_mysql(default.file = path.expand("~/.my.cnf"), group = "client",
#'                   user = NULL, password = NULL, dbname = "fec")
#' }
#' 
#' fec <- etl("fec", db, dir = "~/dumps/fec")
#' fec %>%
#'   etl_extract() %>%
#'   etl_transform() %>%
#'   etl_load(schema = TRUE)
#' }
etl_load.etl_fec <- function(obj, schema = FALSE, years = 2012, ...) {
  
  if (methods::is(obj$con, "DBIConnection")) {
    if (schema == TRUE & inherits(obj, "src_mysql")) {
      schema <- get_schema(obj, schema_name = "init", pkg = "fec")
    }
    if (!missing(schema)) {
      if (file.exists(as.character(schema))) {
        dbRunScript(obj$con, schema, ...)
      }
    }
  }
  
  # write the table directly to the DB
  message("Writing FEC data to the database...")
  lcl <- list.files(attr(obj, "load_dir"), full.names = TRUE)
  tablenames <- c("candidates", "committees", "contributions", "individuals")
  
  mapply(DBI::dbWriteTable, name = tablenames, value = lcl, 
         MoreArgs = list(conn = obj$con, append = TRUE, ... = ...))

  invisible(obj)
}

