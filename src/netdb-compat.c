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

/*
 * Copyright (c) 1987, 1993
 *    The Regents of the University of California.  All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 4. Neither the name of the University nor the names of its contributors
 *    may be used to endorse or promote products derived from this software
 *    without specific prior written permission.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

/*
 * Portions Copyright (c) 1996-1999 by Internet Software Consortium.
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND INTERNET SOFTWARE CONSORTIUM DISCLAIMS
 * ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL INTERNET SOFTWARE
 * CONSORTIUM BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
 * DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR
 * PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS
 * ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS
 * SOFTWARE.
 */

static const char *h_errlist[] =
{
	"Resolver Error 0 (no error)",
	"Unknown host",				/* 1 HOST_NOT_FOUND */
	"Host name lookup failure",		/* 2 TRY_AGAIN */
	"Unknown server error",			/* 3 NO_RECOVERY */
	"No address associated with name",	/* 4 NO_ADDRESS */
};
#define h_nerr (int)(sizeof h_errlist / sizeof h_errlist[0])


const char *hstrerror(int err)
{
	if (err < 0)
		return "Resolver internal error";
	else if (err < h_nerr)
		return h_errlist[err];
	
	return "Unknown resolver error";
}

