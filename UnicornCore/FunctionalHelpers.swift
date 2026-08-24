import Foundation

// MARK: - Precedence Groups

precedencegroup ForwardApplication {
    associativity: left
    higherThan: AssignmentPrecedence
}

precedencegroup MonadicBind {
    associativity: left
    higherThan: ForwardApplication
}

// MARK: - Operators

infix operator |>: ForwardApplication
infix operator >>=: MonadicBind

// MARK: - Implementation

/// Forward Application Operator (Pipeline)
/// Transforms `f(x)` into `x |> f`.
/// Useful for piping data through a series of transformations.
@discardableResult
func |> <A, B>(x: A, f: (A) -> B) -> B {
    return f(x)
}

/// Applies the Optional bind behavior behind `>>=`.
/// Kept as a named function so cross-module tests can exercise the implementation on Swift SDKs
/// that declare a conflicting `>>=` precedence.
func bindOptional<A, B>(_ value: A?, using transform: (A) -> B?) -> B? {
    return value.flatMap(transform)
}

/// Monadic Bind Operator for Optionals
/// Chains operations that return optionals, short-circuiting on nil.
/// This is the functional equivalent of `flatMap`.
func >>= <A, B>(x: A?, f: (A) -> B?) -> B? {
    return bindOptional(x, using: f)
}

/// Monadic Bind Operator for Result
/// Chains operations that return results, short-circuiting on failure.
/// This is the functional equivalent of `flatMap`.
func >>= <A, B, E>(x: Result<A, E>, f: (A) -> Result<B, E>) -> Result<B, E> {
    return x.flatMap(f)
}
