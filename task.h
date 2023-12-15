#include <fcontext.h>

#include "ljx.h"

static const size_t TASK_DEFAULT_STACK_SIZE = 128 * 1024; // 128K

struct task_t {
    task_t * parent {0};
    fcontext_t ctx {0};
    fcontext_stack_t stack {0, 0};
    void * value {0};
    bool completed {0};
};

inline thread_local task_t main_task;
inline thread_local task_t * this_task = &main_task;

template<typename F>
struct task : task_t {
    typedef F function_type; using value_type = decltype(std::declval<F>()());

    F f;

    task() {}

    task(size_t stack_size, F && f) : f(std::forward<F>(f)) {
        this->stack = create_fcontext_stack(stack_size);

        this->ctx = make_fcontext(stack.sptr, stack.ssize, [](fcontext_transfer_t t) {
            task & self = activate(t); self.f(); self.completed = true; self.yield();
            fatal("task completed");
        });
    }

    task(F && f) : task(TASK_DEFAULT_STACK_SIZE, std::forward<F>(f)) {}

    ~task() { if(stack.sptr) { destroy_fcontext_stack(&stack); } }

    static task & activate(fcontext_transfer_t const & t) {
        auto self = (task_t *)t.data;
        
        this_task->ctx = t.ctx; self->parent = this_task; this_task = self;
        
        return *(task *)self;
    }

    value_type & yield(value_type const & x) {
        parent->value= (void *)&x; activate(jump_fcontext(parent->ctx, parent)); return *(value_type *)this_task->value;
    }

    value_type & yield() { return yield(value_type()); }

    value_type & resume(value_type const & x) {
        ok = !(this->completed || this->ctx == nullptr);

        this->value = (void *)&x; activate(jump_fcontext(this->ctx, this)); return *(value_type *)this_task->value;
    }

    value_type & resume() { return resume(value_type()); }

    value_type & operator()(value_type && x) { return resume(std::forward<value_type>(x)); }

    value_type & operator()() { return resume(); }

    task(task && other) = delete;
    task(const task & other) = delete;
    task & operator=(task && other) = delete;
    task & operator=(const task & other) = delete;
};

task() -> task<void()>;

template<typename F>
task(F && f) -> task<F>;

template<typename F>
task(size_t, F && f) -> task<F>;
