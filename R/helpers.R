
#' Produces the possible permutations of a set of nodes
#'
#' @param max A vector of integers. The maximum value of an integer value starting at 0. Defaults to 1. The number of permutation is defined by \code{max}'s length
#' @keywords internal
#' @return A \code{matrix} of permutations
#' @importFrom rlang exprs
#' @examples
#
#' \donttest{
#' CausalQueries:::perm(3)
#' }
perm <- function(max = rep(1, 2)) {

    grid <- sapply(max, function(m) exprs(0:!!m))

    x <- do.call(expand.grid, grid)

    colnames(x) <- NULL

    x
}

#' Get string between two regular expression patterns
#'
#' Returns a substring enclosed by two regular expression patterns. By default returns the name of the arguments being indexed by squared brackets (\code{[]}) in a string containing an expression.
#'
#' @param x A character string.
#' @param left A character string. Regular expression to serve as look ahead.
#' @param right A character string. Regular expression to serve as a look behind.
#' @param rm_left An integer. Number of bites after left-side match to remove from result. Defaults to -1.
#' @param rm_right An integer. Number of bites after right-side match to remove from result. Defaults to 0.
#' @return A character vector.
#' @keywords internal
#' @examples
#' a <- '(XX[Y=0] == 1) > (XX[Y=1] == 0)'
#' CausalQueries:::st_within(a)
#' b <- '(XXX[[Y=0]] == 1 + XXX[[Y=1]] == 0)'
#' CausalQueries:::st_within(b)

st_within <- function(x, left = "[^_[:^punct:]]|\\b", right = "\\[", rm_left = 0, rm_right = -1) {
    if (!is.character(x))
        stop("`x` must be a string.")
    puncts <- gregexpr(left, x, perl = TRUE)[[1]]
    stops <- gregexpr(right, x, perl = TRUE)[[1]]

    # only index the first of the same boundary when there are consecutive ones (eg. '[[')
    consec_brackets <- diff(stops)
    if (any(consec_brackets == 1)) {
        remov <- which(consec_brackets == 1) + 1
        stops <- stops[-remov]
    }

    # find the closest punctuation or space
    starts <- sapply(stops, function(s) {
        dif <- s - puncts
        dif <- dif[dif > 0]
        ifelse(length(dif) == 0, ret <- NA, ret <- puncts[which(dif == min(dif))])
        return(ret)
    })
    drop <- is.na(starts) | is.na(stops)
    sapply(1:length(starts), function(i) if (!drop[i])
        substr(x, starts[i] + rm_left, stops[i] + rm_right))
}

#' Recursive substitution
#'
#' Applies \code{gsub()} from multiple patterns to multiple replacements with 1:1 mapping.
#' @return Returns multiple expression with substituted elements
#' @keywords internal
#' @param x A character vector.
#' @param pattern_vector A character vector.
#' @param replacement_vector A character vector.
#' @param ... Options passed onto \code{gsub()} call.
#'
gsub_many <- function(x, pattern_vector, replacement_vector, ...) {
    if (!identical(length(pattern_vector), length(replacement_vector)))
        stop("pattern and replacement vectors must be the same length")
    for (i in seq_along(pattern_vector)) {
        x <- gsub(pattern_vector[i], replacement_vector[i], x, ...)
    }
    x
}

#' Clean condition
#'
#' Takes a string specifying condition and returns properly spaced string.
#' @keywords internal
#' @return A properly spaced string.
#' @param condition A character string. Condition that refers to a unique position (possible outcome) in a nodal type.
clean_condition <- function(condition) {
    spliced <- strsplit(condition, split = "")[[1]]
    spaces <- grepl("[[:space:]]", spliced, perl = TRUE)
    paste(spliced[!spaces], collapse = " ")
}

#' Interpret or find position in nodal type
#'
#' Interprets the position of one or more digits (specified by \code{position}) in a nodal type. Alternatively returns nodal type digit positions that correspond to one or more given \code{condition}.
#' @inheritParams CausalQueries_internal_inherit_params
#' @param condition A vector of characters. Strings specifying the child node, followed by '|' (given) and the values of its parent nodes in \code{model}.
#' @param position A named list of integers. The name is the name of the child node in \code{model}, and its value a vector of digit positions in that node's nodal type to be interpreted. See `Details`.
#' @return A named \code{list} with interpretation of positions of the digits in a nodal type
#' @details A node for a child node X with \code{k} parents has a nodal type represented by X followed by \code{2^k} digits. Argument \code{position} allows user to interpret the meaning of one or more digit positions in any nodal type. For example \code{position = list(X = 1:3)} will return the interpretation of the first three digits in causal types for X. Argument \code{condition} allows users to query the digit position in the nodal type by providing instead the values of the parent nodes of a given child. For example, \code{condition = 'X | Z=0 & R=1'} returns the digit position that corresponds to values X takes when Z = 0 and R = 1.
#' @examples
#' model <- make_model('R -> X; Z -> X; X -> Y')
#' #Example using digit position
#' interpret_type(model, position = list(X = c(3,4), Y = 1))
#' #Example using condition
#' interpret_type(model, condition = c('X | Z=0 & R=1', 'X | Z=0 & R=0'))
#' #Return interpretation of all digit positions of all nodes
#' interpret_type(model)
#' @export
interpret_type <- function(model, condition = NULL, position = NULL) {
    if (!is.null(condition) & !is.null(position))
        stop("Must specify either `query` or `nodal_position`, but not both.")
    parents <- get_parents(model)
    types <- lapply(lapply(parents, length), function(l) perm(rep(1, l)))

    if (is.null(position)) {
        position <- lapply(types, function(i) ifelse(length(i) == 0, return(NA), return(1:nrow(i))))
    } else {
        if (!all(names(position) %in% names(types)))
            stop("One or more names in `position` not found in model.")
    }

    interpret <- lapply(1:length(position), function(i) {
        positions <- position[[i]]
        type <- types[[names(position)[i]]]
        pos_elements <- type[positions, ]

        if (!all(is.na(positions))) {
            interpret <- sapply(1:nrow(pos_elements), function(row) paste0(parents[[names(position)[i]]],
                " = ", pos_elements[row, ], collapse = " & "))
            interpret <- paste0(paste0(c(names(position)[i], " | "), collapse = ""), interpret)
            # Create 'Y*[*]**'-type representations
            asterisks <- rep("*", nrow(type))
            asterisks_ <- sapply(positions, function(s) {
                if (s < length(asterisks)) {
                  if (s == 1)
                    paste0(c("[*]", asterisks[(s + 1):length(asterisks)]), collapse = "") else paste0(c(asterisks[1:(s - 1)], "[*]", asterisks[(s + 1):length(asterisks)]),
                    collapse = "")
                } else {
                  paste0(c(asterisks[1:(s - 1)], "[*]"), collapse = "")
                }
            })
            display <- paste0(names(position)[i], asterisks_)
        } else {
            interpret <- paste0(paste0(c(names(position)[i], " = "), collapse = ""), c(0, 1))
            display <- paste0(names(position)[i], c(0, 1))
        }
        data.frame(node = names(position)[i], position = position[[i]], display = display, interpretation = interpret,
            stringsAsFactors = FALSE)
    })

    names(interpret) <- names(position)

    if (!is.null(condition)) {
        conditions <- sapply(condition, clean_condition)
        interpret_ <- lapply(interpret, function(i) {
            slct <- sapply(conditions, function(cond) {
                a <- trimws(strsplit(cond, "&|\\|")[[1]])
                sapply(i$interpretation, function(bi) {
                  b <- trimws(strsplit(bi, "&|\\|")[[1]])
                  all(a %in% b)
                })
            })
            i <- i[rowSums(slct) > 0, ]
            if (nrow(i) == 0)
                i <- NULL
            i
        })
        interpret <- interpret_[!sapply(interpret_, is.null)]
    }

    return(interpret)
}

#' Expand wildcard
#'
#' Expand statement containing wildcard
#'
#' @inheritParams CausalQueries_internal_inherit_params
#' @param to_expand A character vector of length 1L.
#' @param verbose Logical. Whether to print expanded query on the console.
#' @return A character string with the expanded expression. Wildcard '.' is replaced by 0 and 1.
#' @importFrom rlang expr
#' @export
#' @examples
#'
#' # Position of parentheses matters for type of expansion
#' # In the "global expansion" versions of the entire statement are joined
#' expand_wildcard('(Y[X=1, M=.] > Y[X=1, M=.])')
#' # In the "local expansion" versions of indicated parts are joined
#' expand_wildcard('(Y[X=1, M=.]) > (Y[X=1, M=.])')
#'
#' # If parentheses are missing global expansion used.
#' expand_wildcard('Y[X=1, M=.] > Y[X=1, M=.]')
#'
#' # Expressions not requiring expansion are allowed
#' expand_wildcard('(Y[X=1])')
#'
expand_wildcard <- function(to_expand, join_by = "|", verbose = TRUE) {
    orig <- st_within(to_expand, left = "\\(", right = "\\)", rm_left = 1)
    if (is.list(orig)) {
        if (is.null(orig[[1]])){
            message("No parentheses indicated. Global expansion assumed. See expand_wildcard.")
        orig <- to_expand}
    }
    skeleton <- gsub_many(to_expand, orig, paste0("%expand%", 1:length(orig)), fixed = TRUE)
    expand_it <- grepl("\\.", orig)

    expanded_types <- lapply(1:length(orig), function(i) {
        if (!expand_it[i])
            return(orig[i]) else {
            exp_types <- strsplit(orig[i], ".", fixed = TRUE)[[1]]
            a <- gregexpr("\\w{1}\\s*(?=(=\\s*\\.){1})", orig[i], perl = TRUE)
            matcha <- trimws(unlist(regmatches(orig[i], a)))
            rep_n <- sapply(unique(matcha), function(e) sum(matcha == e))
            n_types <- length(unique(matcha))
            grid <- replicate(n_types, expr(c(0, 1)))
            type_values <- do.call(expand.grid, grid)
            colnames(type_values) <- unique(matcha)

            apply(type_values, 1, function(s) {
                to_sub <- paste0(colnames(type_values), "(\\s)*=(\\s)*$")
                subbed <- gsub_many(exp_types, to_sub, paste0(colnames(type_values), "=", s), perl = TRUE)
                paste0(subbed, collapse = "")
            })
        }
    })

    if (!is.null(join_by)) {
        oper <- sapply(expanded_types, function(l) {
            paste0(l, collapse = paste0(" ", join_by, " "))
        })

        oper_return <- gsub_many(skeleton, paste0("%expand%", 1:length(orig)), oper)


    } else {
        oper <- do.call(cbind, expanded_types)
        oper_return <- apply(oper, 1, function(i) gsub_many(skeleton, paste0("%expand%", 1:length(orig)),
            i))
    }
    if (verbose) {
        cat("Generated expanded expression:\n")
        cat(unlist(oper_return), sep = "\n")
    }
    oper_return
}



#' Get parameter names
#'
#' Parameter names taken from \code{P} matrix or model if no \code{P}  matrix provided
#'
#' @inheritParams CausalQueries_internal_inherit_params
#' @param include_paramset Logical. Whether to include the param set prefix as part of the name.
#' @return A character vector with the names of the parameters in the model
#' @export
#' @examples
#'
#' get_parameter_names(make_model('X->Y'))
#'
get_parameter_names <- function(model, include_paramset = TRUE) {

    if (include_paramset)
        return(model$parameters_df$param_names)
    if (!include_paramset)

        return(model$parameters_df$nodal_type)


}



#' Whether a query contains an exact string
#' @param var Variable name
#' @param query An expression in string format.
#' @return A logical expression indicating whether a variable is included in a query
#' @keywords internal
#' Used in map_query_to_nodal_types
#'
includes_var <- function(var, query)
    length(grep(paste0("\\<", var, "\\>"), query)) > 0

#' List of nodes contained in query
#' @inheritParams CausalQueries_internal_inherit_params
#' @return A vector indicating which variables are included in a query
#' @keywords internal
var_in_query <- function(model, query) {
    v <- model$nodes
    v[sapply(v, includes_var, query = query)]
}

#' Check whether argument is a model
#'
#' @inheritParams CausalQueries_internal_inherit_params
#' @return An error message if argument is not a model.
#' @keywords internal
is_a_model <- function(model){
  minimum_components <- c("dag", "step","nodes", "statement","nodal_types" )
  missing_components <- !minimum_components %in% names(model)

  if(class(model) != "causal_model")
    stop("Argument 'model' must be of class 'causal_model'")
  if(any(missing_components))
    stop("Model doesn't contain ",
         paste(minimum_components[missing_components], collapse = ", "))
}


#' Check whether a model is improper
#'
#' Compute the sum of causal types probabilities. A model is flagged as improper if the sum is different than one.
#' @inheritParams CausalQueries_internal_inherit_params
#' @return A logical expression indicating whether a model is improper
#' @keywords internal
is_improper <- function(model){
    parameters <- suppressMessages(get_param_dist(model, n_draws = 1, using = "priors"))
    prob_of_s <- get_type_prob(model, model$P, parameters = parameters)
    round(sum(prob_of_s),6) != "1"
}


