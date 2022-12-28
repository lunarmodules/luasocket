#ifndef UNIXDEF_H
#define UNIXDEF_H
/*=========================================================================*\
* Unix domain defines
* LuaSocket toolkit
*
* Provides sockaddr_un on Windows and Unix.
\*=========================================================================*/

#ifdef _WIN32
/* Technically it's possible to include <afunix.h> but it's only available
   on Windows SDK 17134 (Windows 10 1803). */
#ifndef AF_UNIX
#define AF_UNIX 1
#endif

struct sockaddr_un
{
    unsigned short sun_family;
    char sun_path[108];
};
#else
#include <sys/un.h>
#endif /* _WIN32 */

#endif /* UNIXDEF_H */
