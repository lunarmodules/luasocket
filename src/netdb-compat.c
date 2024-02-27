/*
 *	symbian_stubs.c
 *
 *	Copyright (c) Nokia 2004-2005.  All rights reserved.
 *      This code is licensed under the same terms as Perl itself.
 *
 *  netdb-compat.c
 *  Copyright (c) Dima Pulkinen 2024
 *
 */

#include "netdb-compat.h"
#include <string.h>

static const struct protoent protocols[] = {
    { "tcp",	0,	 6 },
    { "udp",	0,	17 }
};

/* The protocol field (the last) is left empty to save both space
 * and time because practically all services have both tcp and udp
 * allocations in IANA. */
static const struct servent services[] = {
    { "http",		0,	  80,	0 }, /* Optimization. */
    { "https",		0,	 443,	0 },
    { "imap",		0,	 143,	0 },
    { "imaps",		0,	 993,   0 },
    { "smtp",		0,	  25,	0 },
    { "irc",		0,	 194,	0 },

    { "ftp",		0,	  21,	0 },
    { "ssh",		0,	  22,	0 },
    { "tftp",		0,	  69,	0 },
    { "pop3",		0,	 110,	0 },
    { "sftp",		0,	 115,	0 },
    { "nntp",		0,	 119,	0 },
    { "ntp",		0,	 123,	0 },
    { "snmp",		0,	 161,	0 },
    { "ldap",		0,	 389,	0 },
    { "rsync",		0,	 873,	0 },
    { "socks",		0,	1080,	0 }
};

struct protoent* getprotobynumber(int number) {
    int i;
    for (i = 0; i < sizeof(protocols)/sizeof(struct protoent); i++)
        if (protocols[i].p_proto == number)
            return (struct protoent*)(&(protocols[i]));
    return 0;
}

struct protoent* getprotobyname(const char* name) {
    int i;
    for (i = 0; i < sizeof(protocols)/sizeof(struct protoent); i++)
        if (strcmp(name, protocols[i].p_name) == 0)
            return (struct protoent*)(&(protocols[i]));
    return 0;
}
    
struct servent* getservbyname(const char* name, const char* proto) {
    int i;
    for (i = 0; i < sizeof(services)/sizeof(struct servent); i++)
        if (strcmp(name, services[i].s_name) == 0)
            return (struct servent*)(&(services[i]));
    return 0;
}

struct servent* getservbyport(int port, const char* proto) {
    int i;
    for (i = 0; i < sizeof(services)/sizeof(struct servent); i++)
        if (services[i].s_port == port)
            return (struct servent*)(&(services[i]));
    return 0;
}

