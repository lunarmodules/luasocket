#include "io.h"

void io_init(p_io io, p_send send, p_recv recv, void *ctx)
{
    io->send = send;
    io->recv = recv;
    io->ctx = ctx;
}
