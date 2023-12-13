#include <stdio.h>
#include <fcontext.h>

void taskfn(fcontext_transfer_t transfer) {
    printf("Hello from taskfn 1!\n");
    transfer = jump_fcontext(transfer.ctx, transfer.data);

    printf("Hello from taskfn 2!\n");
    transfer = jump_fcontext(transfer.ctx, transfer.data);

    printf("Hello from taskfn 3!\n");
    transfer = jump_fcontext(transfer.ctx, transfer.data);
}

int main() {
    printf("Hello World!\n");

    fcontext_stack_t stack = create_fcontext_stack(1024 * 1024);

    fcontext_t ctx = make_fcontext(stack.sptr, stack.ssize, taskfn);

    fcontext_transfer_t transfer = jump_fcontext(ctx, NULL);

    printf("Hello from main 1!\n");

    transfer = jump_fcontext(transfer.ctx, NULL);

    printf("Hello from main 2!\n");

    transfer = jump_fcontext(transfer.ctx, NULL);

    printf("Hello from main 3!\n");

    return 0;
}