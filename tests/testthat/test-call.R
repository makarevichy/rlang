context("call")

# Creation ----------------------------------------------------------------

test_that("character vector must be length 1", {
  expect_error(call2(letters), "must be a length 1 string")
})

test_that("args can be specified individually or as list", {
  out <- call2("f", a = 1, splice(list(b = 2)))
  expect_equal(out, quote(f(a = 1, b = 2)))
})

test_that("creates namespaced calls", {
  expect_identical(call2("fun", foo = quote(baz), .ns = "bar"), quote(bar::fun(foo = baz)))
})

test_that("fails with non-callable objects", {
  expect_error(call2(1), "non-callable")
  expect_error(call2(current_env()), "non-callable")
})

test_that("succeeds with literal functions", {
  expect_error(regex = NA, call2(base::mean, 1:10))
  expect_error(regex = NA, call2(base::list, 1:10))
})


# Standardisation ---------------------------------------------------------

test_that("call_standardise() supports quosures", {
  fn <- function(foo, bar) "Not this one"

  quo <- local({
    fn <- function(baz, quux) "This one"
    quo(fn(this, that))
  })

  exp <- new_quosure(quote(fn(baz = this, quux = that)), quo_get_env(quo))
  expect_identical(call_standardise(quo), exp)
})

test_that("can standardise primitive functions (#473)", {
  expect_identical(call_standardise(foo ~ bar), foo ~ bar)
  expect_identical(call_standardise(quote(1 + 2)), quote(1 + 2))
})


# Modification ------------------------------------------------------------

test_that("can modify formulas inplace", {
  expect_identical(call_modify(~matrix(bar), quote(foo)), ~matrix(bar, foo))
})

test_that("new args inserted at end", {
  call <- quote(matrix(1:10))
  out <- call_modify(call_standardise(call), nrow = 3)
  expect_equal(out, quote(matrix(data = 1:10, nrow = 3)))
})

test_that("new args replace old", {
  call <- quote(matrix(1:10))
  out <- call_modify(call_standardise(call), data = 3)
  expect_equal(out, quote(matrix(data = 3)))
})

test_that("can modify calls for primitive functions", {
  expect_identical(call_modify(~list(), foo = "bar"), ~list(foo = "bar"))
})

test_that("can modify calls for functions containing dots", {
  expect_identical(call_modify(~mean(), na.rm = TRUE), ~mean(na.rm = TRUE))
})

test_that("accepts unnamed arguments", {
  expect_identical(
    call_modify(~get(), "foo", envir = "bar", "baz"),
    ~get(envir = "bar", "foo", "baz")
  )
})

test_that("allows duplicated arguments (#398)", {
  expect_identical(call_modify(~mean(), na.rm = TRUE, na.rm = FALSE), ~mean(na.rm = FALSE))
  expect_identical(call_modify(~mean(), TRUE, FALSE), ~mean(TRUE, FALSE))
  expect_identical(call_modify(~mean(), foo = zap(), foo = zap()), ~mean())
})

test_that("zaps remove arguments", {
  expect_identical(call_modify(quote(foo(bar = )), bar = zap()), quote(foo()))
  expect_identical_(call_modify(quote(foo(bar = , baz = )), !!!rep_named(c("foo", "bar", "baz"), list(zap()))), quote(foo()))
})

test_that("can remove unexisting arguments (#393)", {
  expect_identical(call_modify(quote(foo()), ... = zap()), quote(foo()))
})

test_that("can add a missing argument", {
  expect_identical(call_modify(quote(foo()), bar = expr()), quote(foo(bar = )))
  expect_identical(call_modify(quote(foo()), bar = ), quote(foo(bar = )))
})

test_that("can refer to dots as named argument", {
  expect_error(call_modify(quote(foo()), ... = NULL), "must be `zap\\(\\)` or empty")
  expect_error(call_modify(quote(foo()), ... = "foo"), "must be `zap\\(\\)` or empty")
  expect_identical(call_modify(quote(foo(x, ..., y)), ... = ), quote(foo(x, ..., y)))
  expect_identical(call_modify(quote(foo(x)), ... = ), quote(foo(x, ...)))
  expect_identical(call_modify(quote(foo(x, ..., y)), ... = zap()), quote(foo(x, y)))
})

test_that("can't supply unnamed zaps", {
  expect_error(call_modify(quote(foo(bar)), zap()), "can't be unnamed")
})


# Utils --------------------------------------------------------------

test_that("NULL is a valid language object", {
  expect_true(is_expression(NULL))
})

test_that("is_call() pattern-matches", {
  expect_true(is_call(quote(foo(bar)), "foo"))
  expect_false(is_call(quote(foo(bar)), "bar"))
  expect_true(is_call(quote(foo(bar)), quote(foo)))

  expect_true(is_call(quote(foo(bar)), "foo", n = 1))
  expect_false(is_call(quote(foo(bar)), "foo", n = 2))
  expect_true(is_call(quote(+3), n = 1))
  expect_true(is_call(quote(3 + 3), n = 2))

  expect_true(is_call(quote(foo::bar())), quote(foo::bar()))

  expect_false(is_call(1))
  expect_false(is_call(NULL))
})

test_that("is_call() vectorises name", {
  expect_false(is_call(quote(foo::bar), c("fn", "fn2")))
  expect_true(is_call(quote(foo::bar), c("fn", "::")))

  expect_true(is_call(quote(foo::bar), quote(`::`)))
  expect_true(is_call(quote(foo::bar), list(quote(`@`), quote(`::`))))
  expect_false(is_call(quote(foo::bar), list(quote(`@`), quote(`:::`))))
})

test_that("call_name() handles namespaced and anonymous calls", {
  expect_equal(call_name(quote(foo::bar())), "bar")
  expect_equal(call_name(quote(foo:::bar())), "bar")

  expect_null(call_name(quote(foo@bar())))
  expect_null(call_name(quote(foo$bar())))
  expect_null(call_name(quote(foo[[bar]]())))
  expect_null(call_name(quote(foo()())))
  expect_null(call_name(quote(foo::bar()())))
  expect_null(call_name(quote((function() NULL)())))
})

test_that("call_name() handles formulas and frames", {
  expect_identical(call_name(~foo(baz)), "foo")

  fn <- function() call_name(call_frame())
  expect_identical(fn(), "fn")
})

test_that("call_fn() extracts function", {
  fn <- function() call_fn(call_frame())
  expect_identical(fn(), fn)

  expect_identical(call_fn(~matrix()), matrix)
})

test_that("call_fn() looks up function in `env`", {
  env <- local({
    fn <- function() "foo"
    current_env()
  })
  expect_identical(call_fn(quote(fn()), env = env), env$fn)
})

test_that("Inlined functions return NULL name", {
  call <- quote(fn())
  call[[1]] <- function() {}
  expect_null(call_name(call))
})

test_that("call_args() and call_args_names()", {
  expect_identical(call_args(~fn(a, b)), set_names(list(quote(a), quote(b)), c("", "")))

  fn <- function(a, b) call_args_names(call_frame())
  expect_identical(fn(a = foo, b = bar), c("a", "b"))
})

test_that("qualified and namespaced symbols are recognised", {
  expect_true(is_qualified_call(quote(foo@baz())))
  expect_true(is_qualified_call(quote(foo::bar())))
  expect_false(is_qualified_call(quote(foo()())))

  expect_false(is_namespaced_call(quote(foo@bar())))
  expect_true(is_namespaced_call(quote(foo::bar())))
})

test_that("can specify ns in namespaced predicate", {
  expr <- quote(foo::bar())
  expect_false(is_namespaced_call(expr, quote(bar)))
  expect_true(is_namespaced_call(expr, quote(foo)))
  expect_true(is_namespaced_call(expr, "foo"))
})

test_that("can specify ns in is_call()", {
  expr <- quote(foo::bar())
  expect_true(is_call(expr, ns = NULL))
  expect_false(is_call(expr, ns = ""))
  expect_false(is_call(expr, ns = "baz"))
  expect_true(is_call(expr, ns = "foo"))
  expect_true(is_call(expr, name = "bar", ns = "foo"))
  expect_false(is_call(expr, name = "baz", ns = "foo"))
})

test_that("can check multiple namespaces with is_call()", {
  expect_true(is_call(quote(foo::quux()), ns = c("foo", "bar")))
  expect_true(is_call(quote(bar::quux()), ns = c("foo", "bar")))
  expect_false(is_call(quote(baz::quux()), ns = c("foo", "bar")))
  expect_false(is_call(quote(quux()), ns = c("foo", "bar")))

  expect_false(is_call(quote(baz::quux()), ns = c("foo", "bar", "")))
  expect_true(is_call(quote(quux()), ns = c("foo", "bar", "")))
})

test_that("can unnamespace calls", {
  expect_identical(call_unnamespace(quote(bar(baz))), quote(bar(baz)))
  expect_identical(call_unnamespace(quote(foo::bar(baz))), quote(bar(baz)))
  expect_identical(call_unnamespace(quote(foo@bar(baz))), quote(foo@bar(baz)))
})

test_that("precedence of regular calls", {
  expect_true(call_has_precedence(quote(1 + 2), quote(foo(1 + 2))))
  expect_true(call_has_precedence(quote(foo()), quote(1 + foo())))
})

test_that("precedence of associative ops", {
  expect_true(call_has_precedence(quote(1 + 2), quote(1 + 2 + 3), "lhs"))
  expect_false(call_has_precedence(quote(2 + 3), quote(1 + 2 + 3), "rhs"))
  expect_false(call_has_precedence(quote(1^2), quote(1^2^3), "lhs"))
  expect_true(call_has_precedence(quote(2^3), quote(1^2^3), "rhs"))
})

test_that("call functions type-check their input (#187)", {
  x <- list(a = 1)
  expect_error(call_modify(x, NULL), "must be a quoted call")
  expect_error(call_standardise(x), "must be a quoted call")
  expect_error(call_fn(x), "must be a quoted call")
  expect_error(call_name(x), "must be a quoted call")
  expect_error(call_args(x), "must be a quoted call")
  expect_error(call_args_names(x), "must be a quoted call")

  q <- quo(!!x)
  expect_error(call_modify(q, NULL), "must be a quoted call")
  expect_error(call_standardise(q), "must be a quoted call")
  expect_error(call_fn(q), "must be a quoted call")
  expect_error(call_name(q), "must be a quoted call")
  expect_error(call_args(q), "must be a quoted call")
  expect_error(call_args_names(q), "must be a quoted call")
})

test_that("call_print_type() returns correct enum", {
  expect_error(call_print_type(""), "must be a call")
  expect_identical(call_print_type(quote(foo())), "prefix")

  expect_identical(call_print_type(quote(~a)), "prefix")
  expect_identical(call_print_type(quote(?a)), "prefix")
  expect_identical_(call_print_type(quote(!b)), "prefix")
  expect_identical_(call_print_type(quote(`!!`(b))), "prefix")
  expect_identical_(call_print_type(quote(`!!!`(b))), "prefix")
  expect_identical(call_print_type(quote(+a)), "prefix")
  expect_identical(call_print_type(quote(-a)), "prefix")

  expect_identical(call_print_type(quote(while (a) b)), "special")
  expect_identical(call_print_type(quote(for (a in b) b)), "special")
  expect_identical(call_print_type(quote(repeat a)), "special")
  expect_identical(call_print_type(quote(if (a) b)), "special")
  expect_identical(call_print_type(quote((a))), "special")
  expect_identical(call_print_type(quote({ a })), "special")
  expect_identical(call_print_type(quote(a[b])), "special")
  expect_identical(call_print_type(quote(a[[b]])), "special")

  expect_identical(call_print_type(quote(a ? b)), "infix")
  expect_identical(call_print_type(quote(a ~ b)), "infix")
  expect_identical(call_print_type(quote(a <- b)), "infix")
  expect_identical(call_print_type(quote(a <<- b)), "infix")
  expect_identical(call_print_type(quote(a < b)), "infix")
  expect_identical(call_print_type(quote(a <= b)), "infix")
  expect_identical(call_print_type(quote(a > b)), "infix")
  expect_identical(call_print_type(quote(a >= b)), "infix")
  expect_identical(call_print_type(quote(`=`(a, b))), "infix")
  expect_identical(call_print_type(quote(a == b)), "infix")
  expect_identical(call_print_type(quote(a:b)), "infix")
  expect_identical(call_print_type(quote(a::b)), "infix")
  expect_identical(call_print_type(quote(a:::b)), "infix")
  expect_identical(call_print_type(quote(a := b)), "infix")
  expect_identical(call_print_type(quote(a | b)), "infix")
  expect_identical(call_print_type(quote(a || b)), "infix")
  expect_identical(call_print_type(quote(a & b)), "infix")
  expect_identical(call_print_type(quote(a && b)), "infix")
  expect_identical(call_print_type(quote(a + b)), "infix")
  expect_identical(call_print_type(quote(a - b)), "infix")
  expect_identical(call_print_type(quote(a * b)), "infix")
  expect_identical(call_print_type(quote(a / b)), "infix")
  expect_identical(call_print_type(quote(a ^ b)), "infix")
  expect_identical(call_print_type(quote(a$b)), "infix")
  expect_identical(call_print_type(quote(a@b)), "infix")
  expect_identical(call_print_type(quote(a %% b)), "infix")
  expect_identical(call_print_type(quote(a %>% b)), "infix")

  expect_identical(call_print_type(quote(`?`(a, b, c))), "prefix")
  expect_identical(call_print_type(quote(`~`(a, b, c))), "prefix")
  expect_identical(call_print_type(quote(`<`(a, b, c))), "prefix")
  expect_identical(call_print_type(quote(`<=`(a, b, c))), "prefix")
  expect_identical(call_print_type(quote(`>`(a, b, c))), "prefix")
  expect_identical(call_print_type(quote(`>=`(a, b, c))), "prefix")
  expect_identical(call_print_type(quote(`==`(a, b, c))), "prefix")
  expect_identical(call_print_type(quote(`:`(a, b, c))), "prefix")
  expect_identical(call_print_type(quote(`:=`(a, b, c))), "prefix")
  expect_identical(call_print_type(quote(`|`(a, b, c))), "prefix")
  expect_identical(call_print_type(quote(`||`(a, b, c))), "prefix")
  expect_identical(call_print_type(quote(`&`(a, b, c))), "prefix")
  expect_identical(call_print_type(quote(`&&`(a, b, c))), "prefix")
  expect_identical(call_print_type(quote(`+`(a, b, c))), "prefix")
  expect_identical(call_print_type(quote(`-`(a, b, c))), "prefix")
  expect_identical(call_print_type(quote(`*`(a, b, c))), "prefix")
  expect_identical(call_print_type(quote(`/`(a, b, c))), "prefix")
  expect_identical(call_print_type(quote(`^`(a, b, c))), "prefix")
  expect_identical(call_print_type(quote(`%%`(a, b, c))), "prefix")
  expect_identical(call_print_type(quote(`%>%`(a, b, c))), "prefix")

  expect_identical(call_print_type(quote(`<-`(a, b, c))), "infix")
  expect_identical(call_print_type(quote(`<<-`(a, b, c))), "infix")
  expect_identical(call_print_type(quote(`=`(a, b, c))), "infix")
  expect_identical(call_print_type(quote(`::`(a, b, c))), "infix")
  expect_identical(call_print_type(quote(`:::`(a, b, c))), "infix")
  expect_identical(call_print_type(quote(`$`(a, b, c))), "infix")
  expect_identical(call_print_type(quote(`@`(a, b, c))), "infix")
})

test_that("call_print_fine_type() returns correct enum", {
  expect_error(call_print_fine_type(""), "must be a call")
  expect_identical(call_print_fine_type(quote(foo())), "call")

  expect_identical(call_print_fine_type(quote(~a)), "prefix")
  expect_identical(call_print_fine_type(quote(?a)), "prefix")
  expect_identical_(call_print_fine_type(quote(!b)), "prefix")
  expect_identical_(call_print_fine_type(quote(`!!`(b))), "prefix")
  expect_identical_(call_print_fine_type(quote(`!!!`(b))), "prefix")
  expect_identical(call_print_fine_type(quote(+a)), "prefix")
  expect_identical(call_print_fine_type(quote(-a)), "prefix")

  expect_identical(call_print_fine_type(quote(while (a) b)), "control")
  expect_identical(call_print_fine_type(quote(for (a in b) b)), "control")
  expect_identical(call_print_fine_type(quote(repeat a)), "control")
  expect_identical(call_print_fine_type(quote(if (a) b)), "control")
  expect_identical(call_print_fine_type(quote((a))), "delim")
  expect_identical(call_print_fine_type(quote({ a })), "delim")
  expect_identical(call_print_fine_type(quote(a[b])), "subset")
  expect_identical(call_print_fine_type(quote(a[[b]])), "subset")

  expect_identical(call_print_fine_type(quote(a ? b)), "infix")
  expect_identical(call_print_fine_type(quote(a ~ b)), "infix")
  expect_identical(call_print_fine_type(quote(a <- b)), "infix")
  expect_identical(call_print_fine_type(quote(a <<- b)), "infix")
  expect_identical(call_print_fine_type(quote(a < b)), "infix")
  expect_identical(call_print_fine_type(quote(a <= b)), "infix")
  expect_identical(call_print_fine_type(quote(a > b)), "infix")
  expect_identical(call_print_fine_type(quote(a >= b)), "infix")
  expect_identical(call_print_fine_type(quote(`=`(a, b))), "infix")
  expect_identical(call_print_fine_type(quote(a == b)), "infix")
  expect_identical(call_print_fine_type(quote(a:b)), "infix")
  expect_identical(call_print_fine_type(quote(a::b)), "infix")
  expect_identical(call_print_fine_type(quote(a:::b)), "infix")
  expect_identical(call_print_fine_type(quote(a := b)), "infix")
  expect_identical(call_print_fine_type(quote(a | b)), "infix")
  expect_identical(call_print_fine_type(quote(a || b)), "infix")
  expect_identical(call_print_fine_type(quote(a & b)), "infix")
  expect_identical(call_print_fine_type(quote(a && b)), "infix")
  expect_identical(call_print_fine_type(quote(a + b)), "infix")
  expect_identical(call_print_fine_type(quote(a - b)), "infix")
  expect_identical(call_print_fine_type(quote(a * b)), "infix")
  expect_identical(call_print_fine_type(quote(a / b)), "infix")
  expect_identical(call_print_fine_type(quote(a ^ b)), "infix")
  expect_identical(call_print_fine_type(quote(a$b)), "infix")
  expect_identical(call_print_fine_type(quote(a@b)), "infix")
  expect_identical(call_print_fine_type(quote(a %% b)), "infix")
  expect_identical(call_print_fine_type(quote(a %>% b)), "infix")

  expect_identical(call_print_fine_type(quote(`?`(a, b, c))), "call")
  expect_identical(call_print_fine_type(quote(`~`(a, b, c))), "call")
  expect_identical(call_print_fine_type(quote(`<`(a, b, c))), "call")
  expect_identical(call_print_fine_type(quote(`<=`(a, b, c))), "call")
  expect_identical(call_print_fine_type(quote(`>`(a, b, c))), "call")
  expect_identical(call_print_fine_type(quote(`>=`(a, b, c))), "call")
  expect_identical(call_print_fine_type(quote(`==`(a, b, c))), "call")
  expect_identical(call_print_fine_type(quote(`:`(a, b, c))), "call")
  expect_identical(call_print_fine_type(quote(`:=`(a, b, c))), "call")
  expect_identical(call_print_fine_type(quote(`|`(a, b, c))), "call")
  expect_identical(call_print_fine_type(quote(`||`(a, b, c))), "call")
  expect_identical(call_print_fine_type(quote(`&`(a, b, c))), "call")
  expect_identical(call_print_fine_type(quote(`&&`(a, b, c))), "call")
  expect_identical(call_print_fine_type(quote(`+`(a, b, c))), "call")
  expect_identical(call_print_fine_type(quote(`-`(a, b, c))), "call")
  expect_identical(call_print_fine_type(quote(`*`(a, b, c))), "call")
  expect_identical(call_print_fine_type(quote(`/`(a, b, c))), "call")
  expect_identical(call_print_fine_type(quote(`^`(a, b, c))), "call")
  expect_identical(call_print_fine_type(quote(`%%`(a, b, c))), "call")
  expect_identical(call_print_fine_type(quote(`%>%`(a, b, c))), "call")

  expect_identical(call_print_fine_type(quote(`<-`(a, b, c))), "infix")
  expect_identical(call_print_fine_type(quote(`<<-`(a, b, c))), "infix")
  expect_identical(call_print_fine_type(quote(`=`(a, b, c))), "infix")
  expect_identical(call_print_fine_type(quote(`::`(a, b, c))), "infix")
  expect_identical(call_print_fine_type(quote(`:::`(a, b, c))), "infix")
  expect_identical(call_print_fine_type(quote(`$`(a, b, c))), "infix")
  expect_identical(call_print_fine_type(quote(`@`(a, b, c))), "infix")
})

test_that("call_name() fails with namespaced objects (#670)", {
  expect_error(call_name(~foo::bar), "`call` must be a quoted call")
  expect_error(call_name(~foo:::bar), "`call` must be a quoted call")
})
