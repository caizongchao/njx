#pragma once

#include <utility>

template<typename F>
struct arity_of;
template<typename F>
struct arity_of : arity_of<decltype(&F::operator())> {};
template<typename R, typename... Args>
struct arity_of<R (*)(Args...)> : std::integral_constant<unsigned, sizeof...(Args)> {};
template<typename R, typename C, typename... Args>
struct arity_of<R (C::*)(Args...)> : std::integral_constant<unsigned, sizeof...(Args)> {};
template<typename R, typename C, typename... Args>
struct arity_of<R (C::*)(Args...) const> : std::integral_constant<unsigned, sizeof...(Args)> {};

template<typename F>
using arity_of_v = arity_of<F>::value;

template<typename...>
using of_void = void;

template<typename T>
constexpr bool is_function_v = std::is_function_v<T> || std::is_function_v<std::remove_reference_t<T>> || std::is_function_v<std::remove_pointer_t<T>>;

template<typename T>
using operator_call_of = decltype(&T::operator());

template<typename T, typename = void>
struct is_lambda : std::false_type {};

template<typename T>
struct is_lambda<T, of_void<operator_call_of<std::decay_t<T>>>> : std::true_type {};

template<typename T>
constexpr bool is_lambda_v = is_lambda<T>::value;

template<typename T>
constexpr bool is_invokable_v = is_function_v<T> || is_lambda_v<T>;

template<typename T>
concept of_invokable = is_invokable_v<T>;

template<typename F>
struct function_traits;

template<typename R, typename... A>
struct function_traits<R(A...)> {
    static constexpr size_t arity = sizeof...(A);

    static constexpr bool variadic = false;

    typedef R result;

    typedef std::tuple<A...> args;
};

template<typename F>
struct function_traits : public function_traits<decltype(&F::operator())> {};
template<typename C, typename R, typename... A>
struct function_traits<R (C::*)(A...) const> : function_traits<R(A...)> {};
template<typename C, typename R, typename... A>
struct function_traits<R (C::*)(A...)> : function_traits<R(A...)> {};
template<typename R, typename... A>
struct function_traits<R (*)(A...)> : function_traits<R(A...)> {};
template<typename R, typename... A>
struct function_traits<R (&)(A...)> : function_traits<R(A...)> {};
template<typename R, typename... A>
struct function_traits<R (*)(A..., ...)> : function_traits<R(A...)> {
    static constexpr size_t variadic = true;
};
template<typename R, typename... A>
struct function_traits<R (&)(A..., ...)> : function_traits<R(A...)> {
    static constexpr size_t variadic = true;
};

template<typename F>
struct function;

template<typename R, typename... Args>
struct function<R(Args...)> {
    typedef R (*fx_invoker_type)(void * fx, Args... args);
    typedef void (*fx_dtor_type)(void * fx);

    fx_dtor_type fx_dtor {0}; fx_invoker_type fx_invoker {0}; uintptr_t fx {0};

    ~function() { if(fx_dtor) ((fx_dtor_type)(uintptr_t)fx_dtor)(&fx); }

    function() = default;

    function(function const &) = delete;

    function(function && f) : fx_dtor(f.fx_dtor), fx_invoker(f.fx_invoker), fx(f.fx) {
        f.fx_dtor = 0;
    }

    template<typename F>
    function(F && f) {
        typedef std::remove_reference_t<F> fx_type; typedef function_traits<fx_type> fx_traits;

        const size_t fx_size = sizeof(fx_type);

        fx_invoker = (fx_invoker_type)&basic_fx_invoker<fx_type, Args...>;

        if constexpr(!(std::is_function_v<fx_type> || (fx_size == 1))) {
            const bool is_trivial = std::is_trivially_destructible_v<fx_type>;

            if constexpr(is_trivial) fx_dtor = 0; else fx_dtor = (fx_dtor_type)&basic_fx_dtor<fx_type>;

            if constexpr(fx_size <= sizeof(uintptr_t)) {
                new(&fx) fx_type(std::forward<fx_type>(f));
            }
            else {
                fx = (uintptr_t) new fx_type(std::forward<fx_type>(f));
            }
        }
    }

    template<typename F, typename... Xs>
    static auto basic_fx_invoker(void * f, Xs... xs) {
        typedef function_traits<F> fx_traits;

        constexpr size_t fx_size = sizeof(F);
        constexpr bool no_return = std::is_void_v<typename fx_traits::result>;

        F * pfx = 0; if(fx_size > 1) {
            if constexpr(fx_size <= sizeof(uintptr_t)) pfx = (F *)f; else pfx = (F *)*(uintptr_t *)f;
        }

        if constexpr(no_return) { (*pfx)(std::forward<Xs>(xs)...); } else { return (*pfx)(std::forward<Xs>(xs)...); }
    }

    template<typename F>
    static void basic_fx_dtor(void * fx) {
        typedef function_traits<F> fx_traits;

        constexpr size_t fx_size = sizeof(F);
        constexpr bool is_trivial = std::is_trivially_destructible_v<F>;

        if constexpr(!is_trivial) {
            if constexpr(fx_size <= sizeof(uintptr_t)) ((F *)fx)->~F(); else delete(F *)*(uintptr_t *)fx;
        }
    }

    template<typename... Xs>
    auto operator()(Xs &&... xs) const {
        return ((fx_invoker_type)(uintptr_t)fx_invoker)((void *)&this->fx, std::forward<Xs>(xs)...);
    }

    operator bool() const { return fx_invoker; }

    template<typename F>
    bool operator==(F && f) const {
        return fx_invoker == f.fx_invoker && fx == f.fx;
    }

    template<typename F>
    function & operator=(F && f) = delete;
};


