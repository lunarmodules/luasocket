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
 *
 * netdb-compat.h
 * Copyright (c) Dima Pulkinen 2024
 *
 */

#ifndef _NETDB_COMPAT_H_
#define _NETDB_COMPAT_H_

#ifdef __cplusplus
extern "C" {
#endif

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

const char *hstrerror(int err);

struct servent *getservbyname(const char *name, const char *proto);
struct servent *getservbyport(int port, const char *proto);

struct protoent *getprotobyname(const char *name);
struct protoent *getprotobynumber(int proto);


#ifdef __cplusplus
}
#endif


#endif
