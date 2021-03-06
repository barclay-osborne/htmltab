#' Produce the table node
#'
#' @param doc the HTML document which can be a file name or a URL or an already parsed document
#'   (by XML's parsing functions)
#' @param which a vector of length one for identification of the table in the document. Either
#'    a numeric vector for the tables' rank or a character vector that describes an XPath for the table
#' @param ... additional arguments passed to htmlParse
#' @return a table node
check_type <- function(doc, which, ...) UseMethod("check_type")

check_type.default <- function(doc, which, ...){
  stop("doc is of unknown type", call. = FALSE)
}

check_type.XMLNodeSet <- function(doc, which, ...){

  Node <- eval.parent(substitute(XML::xmlParse(XML::saveXML(doc[[1]]), list(...))))

  return(Node)
}

check_type.HTMLInternalDocument <- function(doc, which, ...) {
  Node <- doc
  Node <- select_tab(which = which, Node = Node)

  return(Node)
}

check_type.XMLInternalElementNode <- function(doc, which, ...) {
  Node <- doc
  Node <- select_tab(which = which, Node = Node)

  return(Node)
}

check_type.character <- function(doc, which, ...){

  isurl <- is_url(doc)

  if(isurl) {
    doc <- httr::GET(doc)
    doc <- httr::content(doc, "text")
  } else if (file.exists(doc)) {
    doc <- readChar(doc, file.info(doc)$size)
  }

  Node <- eval.parent(substitute(XML::htmlParse(doc, encoding = "UTF-8", list(...))))
  Node <- select_tab(which = which, Node = Node)

  return(Node)
}


#' Selects the table from the HTML Code
#'
#' @param Node the table node
#' @param which a vector of length one for identification of the table in the document. Either
#'    a numeric vector for the tables' rank or a character vector that describes an XPath for the table
#' @param ... additional arguments passed to htmlParse
#' @return a table node
select_tab <- function(which, Node) UseMethod("select_tab")

select_tab.default <- function(which, Node){

  message("Argument 'which' was left unspecified. Choosing first table.")
  Node <- XML::getNodeSet(Node, path = "//table")

  ifstop(cond = length(Node) == 0,
         mess = "Couldn't find a table.")

  Node <- XML::xmlParse(XML::saveXML(Node[[1]]))
  return(Node)
}

select_tab.numeric <- function(which, Node){

  Node <- XML::getNodeSet(Node, path = "//table")

  ifstop(cond = length(Node) < which,
         mess = "Couldn't find the table. Try passing (different) information to the which argument.")

  Node <- XML::xmlParse(XML::saveXML(Node[[which]]))
  return(Node)
}

select_tab.character <- function(which, Node){

  xpath <- paste(which, collapse = " | ")
  Node <- XML::getNodeSet(Node, path = xpath)

  ifstop(cond = is.null(Node[[1]]),
         mess = "Couldn't find the table. Try passing (different) information to the which argument.")

  Node <- XML::xmlParse(XML::saveXML(Node[[1]]))
  return(Node)
}


#' Evaluate and deparse the header argument
#' @param arg the header information
#' @return evaluated header info
eval_header <- function(arg){

  # Parse header string
  header <- rm_str_white(strsplit(arg, "\\+")[[1]])

  those.header <- which(header %in% c("\"\"", "''", "", ".", "NULL"))
  header[those.header] <- "NULL"

  # Check that inbody information are complete
  ifstop(cond = any(header[-1] == "NULL"),
         mess = "You need to provide complete information for the inbody rows.")

  # Evaluate header information
  header <- lapply(header, function(x) eval(parse(text = x)))

  return(header)
}

#' Evaluate and deparse the body argument
#' @param arg the body argument
eval_body <- function(arg){

  body <- rm_str_white(strsplit(arg, "\\+")[[1]])

  those.body <- which(body %in% c("\"\"", "''", "", ".", "NULL"))
  body[those.body] <- "NULL"

  ifstop(cond = length(body) > 1,
         mess = "Your body information is malformed. You may only provide one piece of information.")

  # Evaluate header information
  body <- eval(parse(text = body))

  return(body)
}


#' Normalizes rows to be nested in tr tags, header in thead, body in tbody and numbers them
#'
#' @param table.Node the table node
#' @return the revised table node
normalize_tr <- function(table.Node){

  wrong_tag <- "//trbody"
  x <- has_tag(table.Node, wrong_tag)

  if(isTRUE(x)){
    old.header <- XML::getNodeSet(table.Node, "//trbody/*")
    invisible(new.header <- XML::newXMLNode("tbody"))
    invisible(XML::addChildren(new.header, old.header))
    invisible(XML::replaceNodes(oldNode = XML::getNodeSet(table.Node, "//trbody")[[1]], newNode = new.header))

    warning(sprintf("The code for the HTML table you provided contains invalid table tags ('%s'). The following transformations were applied:\n
                    //trbody -> //tbody \n
                    If you specified an XPath that makes a reference to this tag, this may have caused problems with their identification.", wrong_tag), call. = F)
  }

  #Every row in tr
  node1 <- XML::getNodeSet(table.Node, "//*[name() = 'td' or name() = 'th' and not(parent::tr)][preceding-sibling::*[1]/self::tr]")

  if(length(node1) > 0){

    for(i in 1:length(node1)){

      node.container <- list()
      node.container[[1]] <- node1[[i]]

      gg <- 1
      repeat{
        sibling.node <- XML::getSibling(node.container[[gg]])

        if(is.null(sibling.node)) break
        if(!(XML::xmlName(sibling.node) %in% c("td", "th"))) break

        node.container[[gg + 1]] <- sibling.node
        gg <- gg + 1
      }

      invisible(new.tr <- XML::newXMLNode("tr"))
      invisible(XML::replaceNodes(oldNode = node1[[i]], newNode = new.tr))
      invisible(XML::addChildren(new.tr, node.container))
    }

    warning("The code for the HTML table you provided is malformed. Not all cells are nested in row tags (<tr>). htmltab tried to normalize the table and ensure that all cells are within row tags. If you specified an XPath for body or header elements, this may have caused problems with their identification.", call. = F)

  }

  # Flatten inside table
  nested <- has_tag(table.Node, "/table//table")
  if(nested){
    warning("There is a table inside the target table. htmltab tries to flatten the inner table", call. = F)
    invisible(old.node <- XML::getNodeSet(table.Node,  "/table//table"))
    for(i in 1:length(old.node)){
      invisible(vals <- XML::xmlValue(old.node[[i]]))
      invisible(new.cell <- XML::newXMLNode("td", vals))
      invisible(XML::replaceNodes(oldNode = old.node[[i]], newNode = new.cell))
    }
  }

  #Add tr index
  trs <- XML::getNodeSet(table.Node, "//tr")
  n.trs <- length(trs)
  invisible(lapply(1:n.trs, function(index)  XML::xmlAttrs(trs[[index]]) <- c(HTMLTABtrindex = index)))

  return(table.Node)
  }


#' Remove nuisance elements from the the table code
#'
#' @param table.Node the table node
#' @param rm_superscript logical, denotes whether superscript information should be removed from header and body cells (default value TRUE)
#' @param rm_footnotes logical, denotes whether semantic footer information should be removed (default value TRUE)
#' @param rm_invisible logical, should nodes that are not visible (display:none attribute) be removed?
#' @seealso \code{\link{rm_empty_cols}}
#' @return The revised table node
rm_nuisance <- function(table.Node, rm_superscript, rm_footnotes, rm_invisible){

  if(isTRUE(rm_superscript)){
    invisible(XML::removeNodes(XML::getNodeSet(table.Node, "//sup")))
  }

  if(isTRUE(rm_footnotes)){
    invisible(XML::removeNodes(XML::getNodeSet(table.Node, "//tfoot")))
  }

  if(isTRUE(rm_invisible)){
    invisible(XML::removeNodes(XML::getNodeSet(table.Node, "//*[contains(@style, 'display:none') or @class = 'sortkey']")))
  }

  # Remove empty rows
  invisible(XML::removeNodes(XML::getNodeSet(table.Node, "//tr[not(./*)]")))

  return(table.Node)
}


#' Remove columns which do not have data values
#'
#' @param df a data frame
#' @param header the header vector
#' @return a data frame
#' @seealso \code{\link{rm_nuisance}, \link{rm_empty_rows}}
rm_empty_cols <- function(df, header){

  #This is clumsy but seems to work reasonably well
  #columns are removed when they have:
  #1. No name (V...)
  #2. More than 50% missing values in their column

#  no.col.name <- grep('^V[[:digit:]]', colnames(df))

  empty.cols <- sapply(df, function(x) {
    gg <- is.na(x)
    gg <- length(base::which(gg, TRUE)) / length(x)
  })

  empty.cols <- which(empty.cols > 0.5)
  if(length(empty.cols) > 0) warning(sprintf("Columns [%s] seem to have no data and are removed. Use rm_nodata_cols = F to suppress this behavior.", paste(names(empty.cols), collapse = ",")), call. =  F)
  rm.these <- empty.cols #intersect(empty.cols, no.col.name)

  if(length(rm.these) > 0) {
    df <- df[, -rm.these, drop = F]
  }

  return(df)
}

#' Remove rows which do not have data values
#'
#' @param df a data frame
#' @return a data frame
#' @seealso \code{\link{rm_nuisance}, \link{rm_empty_cols}}
rm_empty_rows <- function(df){
  rm.these <- which(rowSums(is.na(df)) == ncol(df))

  if(length(rm.these) > 0) {
    df <- df[-rm.these,]
  }

  return(df)
}



#
# #' Remove columns which do not have data values
# #'
# #' @param df a data frame
# #' @return a data frame
# #' @seealso \code{\link{rm_nuisance}}
# rm_empty_cols <- function(df){
#
#   #This is clumsy but seems to work reasonably well
#   #columns are removed when they have:
#   #1. No name (V...)
#   #2. More than 50% missing values in their column
#
#   no.col.name <- grep('^V[[:digit:]]', colnames(df))
#
#   empty.cols <- sapply(df, function(col){
#     x <- grepl("[A-Za-z]{1,}", col)
#     x <- length(base::which(x, TRUE)) / length(x)
#   })
#
#   empty.cols <- which(empty.cols < 0.5)
#   rm.these <- intersect(empty.cols, no.col.name)
#
#   if(length(rm.these) > 0) {
#     df <- df[, -rm.these]
#   }
#
#   return(df)
# }
