#ifndef _TM_H
#define _TM_H

typedef struct t_tm_tag {
    int tm_return;
    int tm_block;
    int tm_start;
    int tm_end;
} t_tm;
typedef t_tm *p_tm;

void tm_set(p_tm tm, int tm_block, int tm_return);
int tm_getremaining(p_tm tm);
int tm_getelapsed(p_tm tm);
int tm_gettime(void);
void tm_get(p_tm tm, int *tm_block, int *tm_return);
void tm_markstart(p_tm tm);
void tm_open(lua_State *L);

#endif
