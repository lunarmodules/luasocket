/*
 * Phoenix-RTOS
 *
 * libphoenix
 *
 * netdb.h
 *
 * Copyright 2018 Phoenix Systems
 * Author: Jan Sikorski, Michal Miroslaw
 *
 * This file is part of Phoenix-RTOS.
 *
 * %LICENSE%
 */

#ifndef _LIBPHOENIX_NETDB_H_
#define _LIBPHOENIX_NETDB_H_


#include <sys/socktypes.h>
#include <netinet/intypes.h>
#include <stdint.h>


#ifdef __cplusplus
extern "C" {
#endif


#define AI_PASSIVE     (1 << 0)
#define AI_CANONNAME   (1 << 1)
#define AI_NUMERICHOST (1 << 2)
#define AI_NUMERICSERV (1 << 3)
#define AI_V4MAPPED    (1 << 4)
#define AI_ALL         (1 << 5)
#define AI_ADDRCONFIG  (1 << 6)


#define NI_NOFQDN       (1 << 0)
#define NI_NUMERICHOST  (1 << 1)
#define NI_NAMEREQD     (1 << 2)
#define NI_NUMERICSERV  (1 << 3)
#define NI_NUMERICSCOPE (1 << 4)
#define NI_DGRAM        (1 << 5)

#define NI_MAXHOST 1025
#define NI_MAXSERV 32


#define EAI_BADFLAGS -1
#define EAI_NONAME   -2
#define EAI_AGAIN    -3
#define EAI_FAIL     -4
#define EAI_FAMILY   -6
#define EAI_SOCKTYPE -7
#define EAI_SERVICE  -8
#define EAI_MEMORY   -10
#define EAI_SYSTEM   -11
#define EAI_OVERFLOW -12
/* non-POSIX */
#define EAI_NODATA -5

struct hostent {
	char  *h_name;
	char **h_aliases;
	int    h_addrtype;
	int    h_length;
	char **h_addr_list;
};


struct addrinfo {
	int              ai_flags;
	int              ai_family;
	int              ai_socktype;
	int              ai_protocol;
	socklen_t        ai_addrlen;
	struct sockaddr *ai_addr;
	char            *ai_canonname;
	struct addrinfo *ai_next;
};


enum {
	RESOLVED_OK,
	HOST_NOT_FOUND,
	TRY_AGAIN,
	NO_RECOVERY,
	NO_DATA,
};


struct servent {
	char  *s_name;
	char **s_aliases;
	int    s_port;
	char  *s_proto;
};


struct protoent {
	char *p_name;
	char **p_aliases;
	int p_proto;
};


/* FIXME: not thread-safe */
extern int h_errno;
extern const char *hstrerror(int err);

struct servent *getservbyname(const char *name, const char *proto);
struct servent *getservbyport(int port, const char *proto);

struct hostent *gethostbyname(const char *name);
struct hostent *gethostbyaddr(const void *addr, socklen_t len, int type);


int getnameinfo(const struct sockaddr *addr, socklen_t addrlen,
                char *host, socklen_t hostlen,
                char *serv, socklen_t servlen, int flags);
int getaddrinfo(const char *node, const char *service,
                const struct addrinfo *hints,
                struct addrinfo **res);
void freeaddrinfo(struct addrinfo *res);
const char *gai_strerror(int errcode);


extern struct protoent *getprotobyname(const char *name);


extern struct protoent *getprotobynumber(int proto);


#ifdef __cplusplus
}
#endif


#endif
